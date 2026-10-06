package settingsutil_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// linkOldCopy hard-links path to a second name. A write that truncates path in
// place changes what the link reads too; one that renames a new file over path
// leaves the link holding the old bytes. That is how these tests tell a
// crash-safe write from one a power cut can leave half-done (#2611).
func linkOldCopy(t *testing.T, path string) string {
	t.Helper()
	old := path + ".old"
	if err := os.Link(path, old); err != nil {
		t.Fatalf("link: %v", err)
	}
	return old
}

// assertReplacedWhole checks path was replaced by a new file holding want,
// kept 0600, and that no write temp was left beside it.
func assertReplacedWhole(t *testing.T, path, old, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if !strings.Contains(string(got), want) {
		t.Fatalf("settings file = %s, want it to contain %s", got, want)
	}
	oldData, err := os.ReadFile(old)
	if err != nil {
		t.Fatalf("read old link: %v", err)
	}
	if strings.Contains(string(oldData), want) {
		t.Fatal("settings file was rewritten in place; a power cut mid-write could leave it empty")
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Fatalf("mode = %o, want 600: the file holds the remote access household token", perm)
	}
	entries, err := os.ReadDir(filepath.Dir(path))
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), storageutil.WriteTempPrefix) {
			t.Fatalf("temp %s left behind", e.Name())
		}
	}
}

// TestSave_ReplacesTheFileWhole checks Save writes a new file and renames it
// over settings.json rather than truncating the old one.
func TestSave_ReplacesTheFileWhole(t *testing.T) {
	path := settingsFile(t)
	settingsutil.ResetForTesting(path)
	if err := settingsutil.SetAutoUpdate(false); err != nil {
		t.Fatalf("first save: %v", err)
	}
	old := linkOldCopy(t, path)

	if err := settingsutil.SetAutoUpdate(true); err != nil {
		t.Fatalf("second save: %v", err)
	}

	assertReplacedWhole(t, path, old, `"autoUpdate": true`)
	settingsutil.ResetForTesting(path)
	if !settingsutil.GetAutoUpdate() {
		t.Error("autoUpdate did not survive a reload")
	}
}

// TestMigrate_ReplacesTheFileWhole checks the write-back after a migration
// is crash-safe too: it runs on the first Load after an upgrade, before any
// Save.
func TestMigrate_ReplacesTheFileWhole(t *testing.T) {
	settingsutil.SetMigrationsForTesting(t, func(raw map[string]json.RawMessage) error {
		raw["migrated"] = json.RawMessage("true")
		return nil
	})
	path := settingsFile(t)
	if err := os.WriteFile(path, []byte(`{"autoUpdate":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	old := linkOldCopy(t, path)
	settingsutil.ResetForTesting(path)

	if _, err := settingsutil.Load(); err != nil {
		t.Fatalf("Load: %v", err)
	}

	assertReplacedWhole(t, path, old, `"migrated": true`)
}
