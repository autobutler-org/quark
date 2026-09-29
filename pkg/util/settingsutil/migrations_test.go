package settingsutil_test

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestMigrate_RunsOnceAndRewritesFile checks a file behind the migration list
// is migrated on load, stamped with the new version and written back, and that
// a second load neither runs the step again nor rewrites the file.
func TestMigrate_RunsOnceAndRewritesFile(t *testing.T) {
	runs := 0
	settingsutil.SetMigrationsForTesting(t, func(raw map[string]json.RawMessage) error {
		runs++
		delete(raw, "retiredKey")
		return nil
	})
	path := settingsFile(t)
	if err := os.WriteFile(path, []byte(`{"autoUpdate":true,"retiredKey":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)

	s, err := settingsutil.Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if runs != 1 || s.SettingsVersion != 1 || !s.AutoUpdate {
		t.Fatalf("after load: runs=%d version=%d autoUpdate=%v; want 1, 1, true", runs, s.SettingsVersion, s.AutoUpdate)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "retiredKey") || !strings.Contains(string(data), `"settingsVersion": 1`) {
		t.Errorf("file not rewritten by the migration:\n%s", data)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if _, err := settingsutil.Load(); err != nil {
		t.Fatalf("second Load: %v", err)
	}
	after, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if runs != 1 {
		t.Errorf("migration ran %d times; want once", runs)
	}
	if !after.ModTime().Equal(info.ModTime()) {
		t.Error("an up-to-date file was rewritten")
	}
}

// TestMigrate_UpToDateFileUntouched checks a file already at the current
// version is read as is, byte for byte.
func TestMigrate_UpToDateFileUntouched(t *testing.T) {
	settingsutil.SetMigrationsForTesting(t, func(map[string]json.RawMessage) error {
		t.Error("migration ran on an up-to-date file")
		return nil
	})
	path := settingsFile(t)
	original := `{"settingsVersion":1,"autoUpdate":true}`
	if err := os.WriteFile(path, []byte(original), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetAutoUpdate() {
		t.Error("autoUpdate lost")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != original {
		t.Errorf("file changed:\n%s", data)
	}
}

// TestMigrate_MissingFileStartsCurrent checks no file loads as defaults at
// the current version, so the first Save does not replay history on reload.
func TestMigrate_MissingFileStartsCurrent(t *testing.T) {
	runs := 0
	settingsutil.SetMigrationsForTesting(t, func(map[string]json.RawMessage) error {
		runs++
		return nil
	})
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)

	s, err := settingsutil.Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if s.SettingsVersion != 1 {
		t.Errorf("version = %d; want 1", s.SettingsVersion)
	}
	if err := settingsutil.SetAutoUpdate(true); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetAutoUpdate() {
		t.Error("autoUpdate lost")
	}
	if runs != 0 {
		t.Errorf("migration ran %d times on a file this build wrote; want 0", runs)
	}
}
