package install

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// The unit must launch the binary from the directory the service account can
// write, otherwise self-update can never complete (#1609).
func TestSystemdUnit_RunsFromTheSelfUpdatableDirectory(t *testing.T) {
	if !strings.Contains(systemdServiceContent, "ExecStart="+serviceBinPath) {
		t.Errorf("systemd unit should ExecStart from %s:\n%s", serviceBinPath, systemdServiceContent)
	}
	if strings.Contains(systemdServiceContent, "ExecStart="+legacyBinPath) {
		t.Errorf("systemd unit still starts from the root-owned legacy path %s", legacyBinPath)
	}
}

// Every start reapplies the system setup as root, and a failed setup must not
// keep Quark from starting (#2120).
func TestSystemdUnit_ReappliesSystemSetupBeforeEveryStart(t *testing.T) {
	pre := "ExecStartPre=-+" + serviceBinPath + " install --system-only"
	preAt := strings.Index(systemdServiceContent, pre)
	if preAt < 0 {
		t.Fatalf("systemd unit should carry %q:\n%s", pre, systemdServiceContent)
	}
	if startAt := strings.Index(systemdServiceContent, "ExecStart="); startAt < preAt {
		t.Errorf("ExecStartPre should precede ExecStart:\n%s", systemdServiceContent)
	}
}

func TestSystemdUnit_RunsUnprivileged(t *testing.T) {
	// The whole reason the install layout has to change: this stays unprivileged.
	if !strings.Contains(systemdServiceContent, "User="+serviceUserName) {
		t.Errorf("systemd unit should run as %s:\n%s", serviceUserName, systemdServiceContent)
	}
}

// The path the preflight error tells the operator about must be the path the
// installer actually uses.
func TestInstallLayoutMatchesPreflightMessage(t *testing.T) {
	if serviceBinDir != updateutil.SelfUpdatableBinDir {
		t.Errorf(
			"installer uses %s but the preflight tells operators about %s",
			serviceBinDir, updateutil.SelfUpdatableBinDir,
		)
	}
	if legacyBinPath != updateutil.LegacyBinPath {
		t.Errorf(
			"installer symlinks %s but the preflight tells operators about %s",
			legacyBinPath, updateutil.LegacyBinPath,
		)
	}
	if filepath.Dir(serviceBinPath) != serviceBinDir {
		t.Errorf("%s is not inside %s", serviceBinPath, serviceBinDir)
	}
}

// Group-writable and setgid: the service account can create and rename inside
// the directory, so replaceSelf's same-directory temp file and atomic rename
// both work, while root keeps ownership of the binary itself.
func TestServiceBinDirMode(t *testing.T) {
	if serviceBinDirMode&os.ModeSetgid == 0 {
		t.Error("install directory should be setgid so new files inherit the service group")
	}
	if perm := serviceBinDirMode.Perm(); perm&0o020 == 0 {
		t.Errorf("install directory must be group-writable, got %o", perm)
	}
	if perm := serviceBinDirMode.Perm(); perm&0o002 != 0 {
		t.Errorf("install directory must not be world-writable, got %o", perm)
	}
	if perm := serviceBinDirMode.Perm(); perm&0o010 == 0 {
		t.Errorf("install directory must be group-traversable, got %o", perm)
	}
	// A sticky bit would stop the service renaming over the root-owned binary.
	if serviceBinDirMode&os.ModeSticky != 0 {
		t.Error("install directory must not be sticky; that blocks the atomic rename")
	}
}

// A restricted bounding set caps what sudo gets too, so the service could
// never run a sudoers rule as root (#2115).
func TestSystemdUnit_LeavesTheBoundingSetForSudo(t *testing.T) {
	if strings.Contains(systemdServiceContent, "CapabilityBoundingSet") {
		t.Error("systemd unit restricts the bounding set, so sudo cannot run as root")
	}
	if !strings.Contains(systemdServiceContent, "AmbientCapabilities=CAP_NET_BIND_SERVICE") {
		t.Error("systemd unit must still grant CAP_NET_BIND_SERVICE to bind 80 and 443")
	}
}

func TestBuildServiceFile(t *testing.T) {
	got := buildServiceFile()
	switch runtime.GOOS {
	case "linux":
		if got != systemdServiceContent {
			t.Error("linux should get the systemd unit")
		}
	case "darwin":
		if got != plistServiceContent {
			t.Error("darwin should get the launchd plist")
		}
	}
}

// launchd expects a daemon's plist to be named after its Label (#2228).
func TestPlistNameMatchesLabel(t *testing.T) {
	label := strings.TrimSuffix(plistServiceName, ".plist")
	if !strings.Contains(plistServiceContent, "<string>"+label+"</string>") {
		t.Errorf("plist %s should carry the Label %s:\n%s", plistServiceName, label, plistServiceContent)
	}
}
