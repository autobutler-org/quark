package install

import (
	"os"
	"path/filepath"
	"runtime"
	"strconv"
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

// journald is what gives the Linux service rotation and size limits. The unit
// redirected both streams to unrotated files instead, so `journalctl -u quark`
// showed nothing and the files grew until the disk filled (#2231).
func TestSystemdUnit_LeavesLoggingToJournald(t *testing.T) {
	for _, directive := range []string{"StandardOutput=", "StandardError="} {
		if strings.Contains(systemdServiceContent, directive) {
			t.Errorf(
				"systemd unit sets %s, which takes the logs away from journald:\n%s",
				directive, systemdServiceContent,
			)
		}
	}
}

// Nothing should still point at the unrotated, misleadingly named files.
//
// Matched as whole values rather than substrings: /var/log/quark.err is a
// prefix of the new /var/log/quark.err.log, so a `strings.Contains` fails on a
// correctly migrated plist.
func TestServiceDefinitionsDropTheLegacyLogPaths(t *testing.T) {
	for _, path := range legacyLogPaths {
		for _, directive := range []string{"StandardOutput=append:", "StandardError=append:"} {
			if lineFor(systemdServiceContent, directive+path) != "" {
				t.Errorf("systemd unit still writes to %s", path)
			}
		}
		if strings.Contains(plistServiceContent, "<string>"+path+"</string>") {
			t.Errorf("launchd plist still writes to %s", path)
		}
		if lineFor(newsyslogConfContent, path) != "" {
			t.Errorf("newsyslog config still rotates %s", path)
		}
	}
}

// macOS has no journald, so the plist keeps writing files — but named so a log
// viewer recognizes them. `.app` is the extension for an application bundle.
func TestPlistLogPathsAreNamedAsLogs(t *testing.T) {
	for _, path := range []string{plistLogPath, plistErrLogPath} {
		if filepath.Ext(path) != ".log" {
			t.Errorf("log path %s does not end in .log", path)
		}
		if !strings.Contains(plistServiceContent, "<string>"+path+"</string>") {
			t.Errorf("launchd plist does not write to %s:\n%s", path, plistServiceContent)
		}
	}
	if plistLogPath == plistErrLogPath {
		t.Error("stdout and stderr must not share a path")
	}
}

// A rotation policy is the point: a crash loop repeats cobra's whole usage text
// on every restart, which filled the error log on a real device once.
func TestNewsyslogConfRotatesBothLogs(t *testing.T) {
	if dir := filepath.Dir(newsyslogConfPath); dir != "/etc/newsyslog.d" {
		t.Errorf("newsyslog config is at %s; newsyslog only reads /etc/newsyslog.d", dir)
	}
	for _, path := range []string{plistLogPath, plistErrLogPath} {
		line := lineFor(newsyslogConfContent, path)
		if line == "" {
			t.Fatalf("no newsyslog entry for %s:\n%s", path, newsyslogConfContent)
		}
		fields := strings.Fields(line)
		// logfilename mode count size when [flags]
		if len(fields) < 6 {
			t.Fatalf("newsyslog entry for %s has too few fields: %q", path, line)
		}
		count, err := strconv.Atoi(fields[2])
		if err != nil || count < 1 {
			t.Errorf("newsyslog entry for %s keeps %q generations; want at least 1", path, fields[2])
		}
		// newsyslog reads size in kilobytes, so an unbounded entry is `*`.
		size, err := strconv.Atoi(fields[3])
		if err != nil || size < 1 {
			t.Errorf("newsyslog entry for %s has no size limit (%q)", path, fields[3])
		}
		// Without N, newsyslog signals syslogd, which owns none of these files.
		if !strings.Contains(fields[5], "N") {
			t.Errorf("newsyslog entry for %s should set the N flag, got %q", path, fields[5])
		}
	}
}

// lineFor returns the line of conf whose first whitespace-delimited field is
// exactly value, or "" when there is none.
//
// Whole-field matching, not a prefix: /var/log/quark.err is a prefix of
// /var/log/quark.err.log, and confusing the two is the bug this file guards.
func lineFor(conf, value string) string {
	for line := range strings.SplitSeq(conf, "\n") {
		if fields := strings.Fields(line); len(fields) > 0 && fields[0] == value {
			return line
		}
	}
	return ""
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
