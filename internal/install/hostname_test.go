package install

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/hostnameutil"
)

// Root runs the helper, so the service must not be able to rewrite it.
func TestHostnameHelperOutsideSelfUpdatableDir(t *testing.T) {
	if !filepath.IsAbs(hostnameutil.HelperPath) {
		t.Fatalf("helper path %s is not absolute", hostnameutil.HelperPath)
	}
	if strings.HasPrefix(hostnameutil.HelperPath, serviceBinDir+"/") || strings.HasPrefix(hostnameutil.HelperPath, serviceDataDir+"/") {
		t.Errorf("helper %s sits somewhere the service can write", hostnameutil.HelperPath)
	}
}

// The helper is what sudo trusts, so it checks the name itself. This runs
// only the check, followed by an echo where the rename would be: the test
// never reaches hostnamectl.
func TestHostnameHelperScript_ChecksTheName(t *testing.T) {
	dir := t.TempDir()
	whole := filepath.Join(dir, "set-hostname")
	if err := os.WriteFile(whole, []byte(hostnameHelperContent), 0o755); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command("sh", "-n", whole).CombinedOutput(); err != nil {
		t.Fatalf("sh -n: %v: %s", err, out)
	}
	check := filepath.Join(dir, "check")
	if err := os.WriteFile(check, []byte(hostnameHelperCheck+`printf 'accepted %s' "$name"`+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	run := func(stdin string, args ...string) (string, int) {
		cmd := exec.Command(check, args...)
		cmd.Stdin = strings.NewReader(stdin)
		// A locale where a-z could take in more than ASCII must not matter.
		cmd.Env = append(os.Environ(), "LC_ALL=en_US.UTF-8", "LANG=en_US.UTF-8")
		out, _ := cmd.Output()
		return string(out), cmd.ProcessState.ExitCode()
	}

	for _, name := range []string{"a", "quark", "kitchen-quark", "quark2", "2quark", "a-1", strings.Repeat("a", 63)} {
		if out, code := run(name + "\n"); code != 0 || out != "accepted "+name {
			t.Errorf("name %q: exit %d, output %q; want it accepted", name, code, out)
		}
	}
	for _, name := range []string{
		"", "-kitchen", "kitchen-", "Kitchen", "kitchen quark", " kitchen", "kitchen ", "kitchen.local",
		"kitchen_quark", "quark\u00e9", "kitchen;reboot", "$(reboot)", "`reboot`", "../etc/passwd", "a/b",
		"kitchen\t", "*", "123", "localhost", strings.Repeat("a", 64),
	} {
		if out, code := run(name + "\n"); code != 2 || out != "" {
			t.Errorf("name %q: exit %d, output %q; want exit 2 before anything runs", name, code, out)
		}
	}
	// Only the first line is the name; nothing after it is read as one.
	if out, code := run("kitchen\nreboot\n"); code != 0 || out != "accepted kitchen" {
		t.Errorf("two lines: exit %d, output %q; want the first line alone", code, out)
	}
	// The name never comes in as an argument.
	if out, code := run("kitchen\n", "kitchen"); code != 2 || out != "" {
		t.Errorf("with an argument: exit %d, output %q; want exit 2", code, out)
	}
}

func TestHostnameHelperScript_Renames(t *testing.T) {
	for _, want := range []string{
		"set -eu",
		`hostnamectl set-hostname "$name"`,
		"/etc/hosts",
		"systemctl try-restart avahi-daemon.service",
	} {
		if !strings.Contains(hostnameHelperContent, want) {
			t.Errorf("helper is missing %q", want)
		}
	}
	if !strings.HasPrefix(hostnameHelperContent, hostnameHelperCheck) {
		t.Error("the rename must come after the name check")
	}
}
