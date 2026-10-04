package memutil

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const gib = 1 << 30

func ram(total uint64) func() (uint64, error) {
	return func() (uint64, error) { return total, nil }
}

// TestLimitsFor pins the fractions: the Go heap collects well before the
// cgroup is throttled, and the cgroup is throttled before it is killed, with
// room left over for ffmpeg children and the page cache.
func TestLimitsFor(t *testing.T) {
	got := LimitsFor(4 * gib)
	want := Limits{GoLimit: 4 * gib * 60 / 100, MemoryHigh: 4 * gib * 80 / 100, MemoryMax: 4 * gib * 90 / 100}
	if got != want {
		t.Errorf("LimitsFor(4 GiB) = %+v; want %+v", got, want)
	}
}

type recordedLimit struct {
	called bool
	limit  int64
}

func (r *recordedLimit) set(limit int64) int64 {
	r.called, r.limit = true, limit
	return 0
}

func TestApplyGoLimit_DerivesFromRAM(t *testing.T) {
	var rec recordedLimit
	result, err := ApplyGoLimit(ApplyGoLimitParams{
		TotalRAM:       ram(2 * gib),
		Getenv:         func(string) string { return "" },
		SetMemoryLimit: rec.set,
	})
	if err != nil {
		t.Fatalf("ApplyGoLimit: %v", err)
	}
	want := int64(LimitsFor(2 * gib).GoLimit)
	if !rec.called || rec.limit != want {
		t.Errorf("SetMemoryLimit called=%v with %d; want %d", rec.called, rec.limit, want)
	}
	if result.FromEnv || result.Limit != want || result.TotalRAM != 2*gib {
		t.Errorf("result = %+v; want a %d-byte limit derived from 2 GiB", result, want)
	}
}

// TestApplyGoLimit_EnvWins verifies a GOMEMLIMIT the operator set, which the
// runtime has already applied, is left alone.
func TestApplyGoLimit_EnvWins(t *testing.T) {
	var rec recordedLimit
	result, err := ApplyGoLimit(ApplyGoLimitParams{
		TotalRAM: func() (uint64, error) { t.Error("read RAM although GOMEMLIMIT is set"); return 0, nil },
		Getenv: func(k string) string {
			if k == "GOMEMLIMIT" {
				return "1GiB"
			}
			return ""
		},
		SetMemoryLimit: rec.set,
	})
	if err != nil {
		t.Fatalf("ApplyGoLimit: %v", err)
	}
	if rec.called && rec.limit >= 0 {
		t.Errorf("SetMemoryLimit(%d) called; want GOMEMLIMIT left in force", rec.limit)
	}
	if !result.FromEnv {
		t.Errorf("result = %+v; want FromEnv", result)
	}
}

func TestApplyGoLimit_UnknownRAMLeavesTheRuntimeAlone(t *testing.T) {
	var rec recordedLimit
	_, err := ApplyGoLimit(ApplyGoLimitParams{
		TotalRAM:       func() (uint64, error) { return 0, errors.New("no meminfo") },
		Getenv:         func(string) string { return "" },
		SetMemoryLimit: rec.set,
	})
	if err == nil {
		t.Error("ApplyGoLimit = nil error; want the RAM read's")
	}
	if rec.called {
		t.Errorf("SetMemoryLimit(%d) called with RAM unknown", rec.limit)
	}
}

// fakeSystem is a root directory standing in for /, with systemd booted, and
// a runner that records the commands it was asked to run.
type fakeSystem struct {
	root string
	runs []string
}

func newFakeSystem(t *testing.T, booted bool) *fakeSystem {
	t.Helper()
	root := t.TempDir()
	if booted {
		if err := os.MkdirAll(filepath.Join(root, "run/systemd/system"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return &fakeSystem{root: root}
}

func (f *fakeSystem) run(_ context.Context, name string, args ...string) ([]byte, error) {
	f.runs = append(f.runs, strings.Join(append([]string{name}, args...), " "))
	return nil, nil
}

func (f *fakeSystem) params(total uint64) InstallDropInParams {
	return InstallDropInParams{Root: f.root, Run: f.run, TotalRAM: ram(total)}
}

func TestInstallDropIn_WritesCeilingAndReloads(t *testing.T) {
	sys := newFakeSystem(t, true)
	result, err := InstallDropIn(sys.params(4 * gib))
	if err != nil {
		t.Fatalf("InstallDropIn: %v", err)
	}
	if result.Skipped || !result.Changed {
		t.Fatalf("result = %+v; want the drop-in written", result)
	}
	data, err := os.ReadFile(filepath.Join(sys.root, DropInPath))
	if err != nil {
		t.Fatalf("read drop-in: %v", err)
	}
	limits := LimitsFor(4 * gib)
	for _, line := range []string{
		"[Service]",
		fmt.Sprintf("MemoryHigh=%d", limits.MemoryHigh),
		fmt.Sprintf("MemoryMax=%d", limits.MemoryMax),
	} {
		if !strings.Contains(string(data), line+"\n") {
			t.Errorf("drop-in is missing %q:\n%s", line, data)
		}
	}
	if len(sys.runs) != 1 || sys.runs[0] != "systemctl daemon-reload" {
		t.Errorf("ran %q; want one systemctl daemon-reload", sys.runs)
	}
}

// TestInstallDropIn_Idempotent is the every-start case: ExecStartPre runs
// install again, and with the same RAM nothing is written or reloaded.
func TestInstallDropIn_Idempotent(t *testing.T) {
	sys := newFakeSystem(t, true)
	if _, err := InstallDropIn(sys.params(4 * gib)); err != nil {
		t.Fatalf("first InstallDropIn: %v", err)
	}
	sys.runs = nil
	result, err := InstallDropIn(sys.params(4 * gib))
	if err != nil {
		t.Fatalf("second InstallDropIn: %v", err)
	}
	if result.Changed || len(sys.runs) != 0 {
		t.Errorf("second run changed=%v ran %q; want nothing", result.Changed, sys.runs)
	}
}

// TestInstallDropIn_FollowsTheRAM verifies a release that changes the
// fractions, or a disk moved to a board with more RAM, rewrites the ceiling.
func TestInstallDropIn_FollowsTheRAM(t *testing.T) {
	sys := newFakeSystem(t, true)
	if _, err := InstallDropIn(sys.params(4 * gib)); err != nil {
		t.Fatalf("first InstallDropIn: %v", err)
	}
	result, err := InstallDropIn(sys.params(8 * gib))
	if err != nil {
		t.Fatalf("second InstallDropIn: %v", err)
	}
	data, _ := os.ReadFile(filepath.Join(sys.root, DropInPath))
	if !result.Changed || !strings.Contains(string(data), fmt.Sprintf("MemoryMax=%d\n", LimitsFor(8*gib).MemoryMax)) {
		t.Errorf("changed=%v, drop-in:\n%s\nwant the 8 GiB ceiling", result.Changed, data)
	}
}

// TestInstallDropIn_SkipsWithoutSystemd covers macOS, a container, and an OS
// image build in a chroot, where the RAM is the build host's: nothing is
// written, and the first real start writes it.
func TestInstallDropIn_SkipsWithoutSystemd(t *testing.T) {
	sys := newFakeSystem(t, false)
	result, err := InstallDropIn(sys.params(4 * gib))
	if err != nil {
		t.Fatalf("InstallDropIn: %v", err)
	}
	if !result.Skipped || result.SkipReason == "" {
		t.Errorf("result = %+v; want skipped with a reason", result)
	}
	if _, err := os.Stat(filepath.Join(sys.root, DropInPath)); !os.IsNotExist(err) {
		t.Errorf("drop-in exists (stat err %v); want nothing written", err)
	}
	if len(sys.runs) != 0 {
		t.Errorf("ran %q; want nothing", sys.runs)
	}
}

func TestInstallDropIn_ReportsAFailedReload(t *testing.T) {
	sys := newFakeSystem(t, true)
	params := sys.params(4 * gib)
	params.Run = func(context.Context, string, ...string) ([]byte, error) { return nil, errors.New("boom") }
	if _, err := InstallDropIn(params); err == nil {
		t.Error("InstallDropIn = nil error; want the failed daemon-reload")
	}
}
