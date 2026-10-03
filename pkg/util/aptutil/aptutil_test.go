package aptutil

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// fakeSystem stands in for apt, dpkg and systemd-run: it answers the queries
// Configure makes from canned output and records every command, so no test
// touches the real system.
type fakeSystem struct {
	installed []string // dpkg-query lines, "ii  <pkg>"
	held      []string
	missing   map[string]bool
	calls     [][]string
	failOn    string
}

func (f *fakeSystem) run(_ context.Context, name string, args ...string) ([]byte, error) {
	call := append([]string{name}, args...)
	f.calls = append(f.calls, call)
	if f.failOn != "" && name == f.failOn {
		return nil, errors.New(name + " failed")
	}
	switch {
	case name == "dpkg-query":
		return []byte(strings.Join(f.installed, "\n") + "\n"), nil
	case name == "apt-mark" && args[0] == "showhold":
		return []byte(strings.Join(f.held, "\n") + "\n"), nil
	case name == "apt-mark" && args[0] == "hold":
		f.held = append(f.held, args[1:]...)
	case name == "apt-mark" && args[0] == "unhold":
		f.held = slices.DeleteFunc(f.held, func(p string) bool { return slices.Contains(args[1:], p) })
	}
	return nil, nil
}

func (f *fakeSystem) lookPath(name string) (string, error) {
	if f.missing[name] {
		return "", errors.New("not found")
	}
	return "/usr/bin/" + name, nil
}

func (f *fakeSystem) ran(name, sub string) [][]string {
	var out [][]string
	for _, c := range f.calls {
		if c[0] == name && (sub == "" || (len(c) > 1 && c[1] == sub)) {
			out = append(out, c)
		}
	}
	return out
}

func (f *fakeSystem) params(root string) ConfigureParams {
	return ConfigureParams{Root: root, Run: f.run, LookPath: f.lookPath}
}

var armbianBoard = []string{
	"ii  base-files",
	"ii  linux-image-current-rockchip64",
	"ii  linux-dtb-current-rockchip64",
	"ii  linux-u-boot-rock-5b-current",
	"ii  armbian-bsp-cli-rock-5b-current",
	"ii  armbian-firmware",
	"rc  linux-image-legacy-rockchip64",
	"ii  unattended-upgrades",
}

func TestConfigure_WritesSecurityOnlyConfig(t *testing.T) {
	root := t.TempDir()
	sys := &fakeSystem{installed: armbianBoard}
	res, err := Configure(sys.params(root))
	if err != nil {
		t.Fatalf("Configure: %v", err)
	}
	if res.Skipped || !res.ConfigChanged {
		t.Errorf("result = %+v; want a written config", res)
	}
	data, err := os.ReadFile(filepath.Join(root, UnattendedUpgradesConfigPath))
	if err != nil {
		t.Fatalf("read config: %v", err)
	}
	conf := string(data)
	for _, want := range []string{
		"#clear Unattended-Upgrade::Origins-Pattern;",
		"#clear Unattended-Upgrade::Allowed-Origins;",
		"label=Debian-Security",
		`APT::Periodic::Unattended-Upgrade "1";`,
		`Unattended-Upgrade::Automatic-Reboot "false";`,
	} {
		if !strings.Contains(conf, want) {
			t.Errorf("config lacks %q:\n%s", want, conf)
		}
	}
	if strings.Contains(conf, "Automatic-Reboot-Time") {
		t.Errorf("config schedules a reboot:\n%s", conf)
	}
	// Only the security pocket: no plain Debian, no Armbian origin.
	if strings.Contains(conf, "label=Debian\"") || strings.Contains(strings.ToLower(conf), "origin=armbian") {
		t.Errorf("config allows a non-security origin:\n%s", conf)
	}
}

func TestConfigure_IsIdempotent(t *testing.T) {
	root := t.TempDir()
	sys := &fakeSystem{installed: armbianBoard}
	if _, err := Configure(sys.params(root)); err != nil {
		t.Fatalf("first Configure: %v", err)
	}
	sys.calls = nil
	res, err := Configure(sys.params(root))
	if err != nil {
		t.Fatalf("second Configure: %v", err)
	}
	if res.ConfigChanged || len(res.Held) != 0 || res.InstallQueued {
		t.Errorf("second result = %+v; want nothing changed", res)
	}
	if got := sys.ran("apt-mark", "hold"); len(got) != 0 {
		t.Errorf("second run held again: %v", got)
	}
}

func TestConfigure_HoldsInstalledKernelAndBoardPackages(t *testing.T) {
	sys := &fakeSystem{installed: armbianBoard, held: []string{"linux-dtb-current-rockchip64"}}
	res, err := Configure(sys.params(t.TempDir()))
	if err != nil {
		t.Fatalf("Configure: %v", err)
	}
	want := []string{
		"armbian-bsp-cli-rock-5b-current",
		"armbian-firmware",
		"linux-image-current-rockchip64",
		"linux-u-boot-rock-5b-current",
	}
	if !slices.Equal(res.Held, want) {
		t.Errorf("Held = %v; want %v (installed, not yet held, removed ones skipped)", res.Held, want)
	}
	holds := sys.ran("apt-mark", "hold")
	if len(holds) != 1 || !slices.Equal(holds[0][2:], want) {
		t.Errorf("apt-mark hold calls = %v; want one call for %v", holds, want)
	}
}

func TestConfigure_QueuesInstallWhenUnattendedUpgradesMissing(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "run/systemd/system"), 0o755); err != nil {
		t.Fatal(err)
	}
	sys := &fakeSystem{installed: []string{"ii  linux-image-current-meson64"}}
	res, err := Configure(sys.params(root))
	if err != nil {
		t.Fatalf("Configure: %v", err)
	}
	if !res.InstallQueued {
		t.Errorf("InstallQueued = false; want the install handed to systemd-run")
	}
	runs := sys.ran("systemd-run", "")
	if len(runs) != 1 || !strings.Contains(strings.Join(runs[0], " "), "apt-get install") ||
		!slices.Contains(runs[0], "--no-block") {
		t.Errorf("systemd-run calls = %v; want one non-blocking apt-get install", runs)
	}
	if got := sys.ran("apt-get", ""); len(got) != 0 {
		t.Errorf("apt-get ran inline: %v; want it only inside systemd-run", got)
	}
}

func TestConfigure_LeavesInstallWithoutRunningSystemd(t *testing.T) {
	sys := &fakeSystem{installed: []string{"ii  linux-image-current-meson64"}}
	res, err := Configure(sys.params(t.TempDir()))
	if err != nil || res.InstallQueued || len(sys.ran("systemd-run", "")) != 0 {
		t.Errorf("Configure = %+v, %v, calls %v; want no install queued in a chroot", res, err, sys.calls)
	}
}

func TestConfigure_SkipsWithoutApt(t *testing.T) {
	for _, tool := range []string{"apt-get", "apt-mark", "dpkg-query"} {
		t.Run(tool, func(t *testing.T) {
			root := t.TempDir()
			sys := &fakeSystem{missing: map[string]bool{tool: true}}
			res, err := Configure(sys.params(root))
			if err != nil || !res.Skipped || res.SkipReason == "" {
				t.Fatalf("Configure = %+v, %v; want a skip with a reason", res, err)
			}
			if len(sys.calls) != 0 {
				t.Errorf("ran %v; want nothing", sys.calls)
			}
			if _, err := os.Stat(filepath.Join(root, UnattendedUpgradesConfigPath)); !os.IsNotExist(err) {
				t.Errorf("config written without apt: %v", err)
			}
		})
	}
}

func TestConfigure_ReportsFailureButStillWritesConfig(t *testing.T) {
	root := t.TempDir()
	sys := &fakeSystem{installed: armbianBoard, failOn: "apt-mark"}
	if _, err := Configure(sys.params(root)); err == nil {
		t.Fatal("Configure = nil error; want the apt-mark failure")
	}
	if _, err := os.Stat(filepath.Join(root, UnattendedUpgradesConfigPath)); err != nil {
		t.Errorf("config not written after a hold failure: %v", err)
	}
}

func TestReleaseHold_UnholdsAndStaysReleased(t *testing.T) {
	root := t.TempDir()
	sys := &fakeSystem{installed: armbianBoard}
	if _, err := Configure(sys.params(root)); err != nil {
		t.Fatalf("Configure: %v", err)
	}
	rel, err := ReleaseHold(sys.params(root))
	if err != nil {
		t.Fatalf("ReleaseHold: %v", err)
	}
	if len(rel.Released) != 5 {
		t.Errorf("Released = %v; want all five board packages", rel.Released)
	}
	if len(sys.held) != 0 {
		t.Errorf("still held after release: %v", sys.held)
	}

	// The next service start must not take the hold back.
	res, err := Configure(sys.params(root))
	if err != nil {
		t.Fatalf("Configure after release: %v", err)
	}
	if !res.HoldReleased || len(res.Held) != 0 || len(sys.held) != 0 {
		t.Errorf("Configure after release = %+v, held %v; want the hold left off", res, sys.held)
	}

	// Removing the marker restores the hold.
	if err := os.Remove(filepath.Join(root, HoldReleasedMarkerPath)); err != nil {
		t.Fatalf("remove marker: %v", err)
	}
	if res, err := Configure(sys.params(root)); err != nil || len(res.Held) != 5 {
		t.Errorf("Configure after marker removed = %+v, %v; want the five packages held again", res, err)
	}
}
