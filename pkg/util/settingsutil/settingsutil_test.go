package settingsutil_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// settingsFile returns the path used by settingsutil during the test.
func settingsFile(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "settings.json")
}

func TestGetSetRemoteAccess_RoundTrip(t *testing.T) {
	settingsutil.ResetForTesting(settingsFile(t))

	if settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=false with no settings file")
	}
	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatalf("SetRemoteAccess enable: %v", err)
	}
	if !settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=true after enable")
	}
	if err := settingsutil.SetRemoteAccess(false); err != nil {
		t.Fatalf("SetRemoteAccess disable: %v", err)
	}
	if settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=false after disable")
	}
}

func TestGetRemoteAccess_PersistsAcrossReset(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)

	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatalf("SetRemoteAccess: %v", err)
	}

	// Simulate a process restart: reset in-memory cache so next read comes from disk.
	settingsutil.ResetForTesting(path)

	if !settingsutil.GetRemoteAccess() {
		t.Error("expected enabled=true after reload from disk")
	}
}

// TestLegacyAuthKey_IgnoredAndDropped verifies a settings.json written before
// #1876, which still carries remoteAccessAuthKey, parses and keeps its other
// settings, and that the next save drops the stale key.
func TestLegacyAuthKey_IgnoredAndDropped(t *testing.T) {
	path := settingsFile(t)
	legacy := `{"autoUpdate":true,"remoteAccessEnabled":true,"remoteAccessAuthKey":"hskey-old","devMode":false}`
	if err := os.WriteFile(path, []byte(legacy), 0600); err != nil {
		t.Fatalf("write legacy settings: %v", err)
	}
	settingsutil.ResetForTesting(path)

	if !settingsutil.GetRemoteAccess() || !settingsutil.GetAutoUpdate() {
		t.Fatal("legacy settings did not parse: want remote access and auto-update on")
	}
	if err := settingsutil.SetAutoUpdate(true); err != nil {
		t.Fatalf("SetAutoUpdate: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read settings: %v", err)
	}
	if strings.Contains(string(data), "remoteAccessAuthKey") {
		t.Errorf("settings still carry the auth key after a save:\n%s", data)
	}
}

func TestSettingsFile_Permissions(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)

	if err := settingsutil.SetRemoteAccess(true); err != nil {
		t.Fatalf("SetRemoteAccess: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat settings file: %v", err)
	}
	if mode := info.Mode().Perm(); mode != 0600 {
		t.Errorf("settings file mode %04o, want 0600", mode)
	}
}
