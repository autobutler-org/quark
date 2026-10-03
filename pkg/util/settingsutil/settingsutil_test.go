package settingsutil_test

import (
	"bytes"
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

// TestAuthSaltSecret checks the salt secret is made once and survives a
// restart, which ResetForTesting on the same file stands in for.
func TestAuthSaltSecret(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	settingsutil.ResetForTesting(path)
	t.Cleanup(func() { settingsutil.ResetForTesting("") })

	first, err := settingsutil.AuthSaltSecret()
	if err != nil || len(first) != 32 {
		t.Fatalf("AuthSaltSecret = %d bytes, %v; want 32", len(first), err)
	}
	settingsutil.ResetForTesting(path)
	second, err := settingsutil.AuthSaltSecret()
	if err != nil || !bytes.Equal(first, second) {
		t.Errorf("AuthSaltSecret after a restart = %x, %v; want %x", second, err, first)
	}
}

// TestAuthSaltSecret_SurvivesStaleSave checks a save of settings read before
// the secret existed, which is what a setter racing its first use does, keeps
// the secret in the cache and in the file.
func TestAuthSaltSecret_SurvivesStaleSave(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	settingsutil.ResetForTesting(path)
	t.Cleanup(func() { settingsutil.ResetForTesting("") })

	stale, err := settingsutil.Load()
	if err != nil {
		t.Fatal(err)
	}
	secret, err := settingsutil.AuthSaltSecret()
	if err != nil {
		t.Fatal(err)
	}
	stale.AutoUpdate = true
	if err := settingsutil.Save(stale); err != nil {
		t.Fatal(err)
	}

	if got, err := settingsutil.AuthSaltSecret(); err != nil || !bytes.Equal(got, secret) {
		t.Errorf("secret after a stale save = %x, %v; want %x", got, err, secret)
	}
	settingsutil.ResetForTesting(path)
	if got, err := settingsutil.AuthSaltSecret(); err != nil || !bytes.Equal(got, secret) {
		t.Errorf("secret on disk after a stale save = %x, %v; want %x", got, err, secret)
	}
	if !settingsutil.GetAutoUpdate() {
		t.Error("the stale save's own change was lost")
	}
}
