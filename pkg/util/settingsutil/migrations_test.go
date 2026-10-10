package settingsutil_test

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// TestMigrate_RunsOnceOnImport checks a file behind the migration list is
// migrated as it is imported, that the file itself is set aside as it was,
// and that a restart does not run the step again.
func TestMigrate_RunsOnceOnImport(t *testing.T) {
	runs := 0
	settingsutil.SetMigrationsForTesting(t, func(raw map[string]json.RawMessage) error {
		runs++
		raw["themeColor"] = json.RawMessage(`"ocean"`)
		return nil
	})
	path := settingsFile(t)
	original := `{"autoUpdate":true}`
	if err := os.WriteFile(path, []byte(original), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)

	s, err := settingsutil.Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if runs != 1 || s.SettingsVersion != 1 || !s.AutoUpdate || s.ThemeColor != "ocean" {
		t.Fatalf("after import: runs=%d version=%d autoUpdate=%v themeColor=%q; want 1, 1, true, ocean",
			runs, s.SettingsVersion, s.AutoUpdate, s.ThemeColor)
	}
	if kept, err := os.ReadFile(path + ".imported"); err != nil || string(kept) != original {
		t.Errorf("settings.json.imported = %q, %v; want the file as it was", kept, err)
	}

	settingsutil.ResetForTesting(path)
	if settingsutil.GetThemeColor() != "ocean" {
		t.Error("the migrated value did not survive a restart")
	}
	if runs != 1 {
		t.Errorf("migration ran %d times; want once", runs)
	}
}

// TestMigrate_UpToDateFileNotMigrated checks a file already at the current
// version is imported without running a migration.
func TestMigrate_UpToDateFileNotMigrated(t *testing.T) {
	settingsutil.SetMigrationsForTesting(t, func(map[string]json.RawMessage) error {
		t.Error("migration ran on an up-to-date file")
		return nil
	})
	path := settingsFile(t)
	if err := os.WriteFile(path, []byte(`{"settingsVersion":1,"autoUpdate":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetAutoUpdate() {
		t.Error("autoUpdate lost")
	}
}

// TestMigrate_MissingFileStartsCurrent checks no file loads as defaults at
// the current version, and that nothing replays history on a restart.
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
		t.Errorf("migration ran %d times with no file to import; want 0", runs)
	}
}
