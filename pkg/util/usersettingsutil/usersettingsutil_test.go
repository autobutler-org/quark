package usersettingsutil_test

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
)

// TestSaveLoad_RoundTripPerAccount checks an account with no file reads as
// the zero settings, that a save is read back, and that two accounts' files
// are separate and written 0600 under user-settings/<id>.json.
func TestSaveLoad_RoundTripPerAccount(t *testing.T) {
	dataDir := t.TempDir()
	got, err := usersettingsutil.Load(usersettingsutil.LoadParams{DataDir: dataDir, UserID: 1})
	if err != nil || got.Settings != (usersettingsutil.Settings{}) {
		t.Fatalf("Load with no file = %+v, %v; want zero settings", got, err)
	}

	for id, themeColor := range map[int64]string{1: "teal", 2: "#0ea5e9"} {
		saved, err := usersettingsutil.Save(usersettingsutil.SaveParams{
			DataDir: dataDir, UserID: id, Settings: usersettingsutil.Settings{ThemeColor: themeColor},
		})
		if err != nil || saved.Settings.ThemeColor != themeColor {
			t.Fatalf("Save(%d) = %+v, %v", id, saved, err)
		}
	}
	for id, themeColor := range map[int64]string{1: "teal", 2: "#0ea5e9"} {
		got, err := usersettingsutil.Load(usersettingsutil.LoadParams{DataDir: dataDir, UserID: id})
		if err != nil || got.Settings.ThemeColor != themeColor {
			t.Errorf("Load(%d) = %+v, %v; want theme color %q", id, got, err, themeColor)
		}
	}

	path := filepath.Join(dataDir, "user-settings", "1.json")
	if path != usersettingsutil.Path(dataDir, 1) {
		t.Errorf("Path = %q, want %q", usersettingsutil.Path(dataDir, 1), path)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != 0o600 {
		t.Errorf("settings file mode = %o, want 600", mode)
	}

	// Clearing the override is a save like any other.
	if _, err := usersettingsutil.Save(usersettingsutil.SaveParams{DataDir: dataDir, UserID: 1}); err != nil {
		t.Fatal(err)
	}
	if got, _ := usersettingsutil.Load(usersettingsutil.LoadParams{DataDir: dataDir, UserID: 1}); got.Settings.ThemeColor != "" {
		t.Errorf("theme color after clearing = %q", got.Settings.ThemeColor)
	}
}

// TestSave_RefusesInvalidThemeColor checks a malformed theme color is ErrInvalid and
// leaves the stored settings alone.
func TestSave_RefusesInvalidThemeColor(t *testing.T) {
	dataDir := t.TempDir()
	if _, err := usersettingsutil.Save(usersettingsutil.SaveParams{
		DataDir: dataDir, UserID: 1, Settings: usersettingsutil.Settings{ThemeColor: "#0EA5E9"},
	}); !errors.Is(err, usersettingsutil.ErrInvalid) {
		t.Errorf("Save with an uppercase color = %v, want ErrInvalid", err)
	}
	if _, err := os.Stat(usersettingsutil.Path(dataDir, 1)); !os.IsNotExist(err) {
		t.Errorf("a refused save wrote a file (stat err %v)", err)
	}
}

// TestDecode checks a body is one JSON object of known fields with a
// well-formed theme color, and that anything else is ErrInvalid.
func TestDecode(t *testing.T) {
	for _, tc := range []struct {
		name, body, want string
		valid            bool
	}{
		{"preset", `{"themeColor":"teal"}`, "teal", true},
		{"custom", `{"themeColor":"#0ea5e9"}`, "#0ea5e9", true},
		{"empty theme color", `{"themeColor":""}`, "", true},
		{"no theme color", `{}`, "", true},
		{"unknown field", `{"themeColor":"teal","theme":"dark"}`, "", false},
		{"only an unknown field", `{"userId":2}`, "", false},
		{"malformed theme color", `{"themeColor":"Teal"}`, "", false},
		{"wrong type", `{"themeColor":7}`, "", false},
		{"not an object", `"teal"`, "", false},
		{"two values", `{"themeColor":"teal"}{"themeColor":"red"}`, "", false},
		{"not JSON", `themeColor=teal`, "", false},
		{"empty body", ``, "", false},
	} {
		got, err := usersettingsutil.Decode(strings.NewReader(tc.body))
		if tc.valid && (err != nil || got.ThemeColor != tc.want) {
			t.Errorf("%s: Decode = %+v, %v; want theme color %q", tc.name, got, err, tc.want)
		}
		if !tc.valid && !errors.Is(err, usersettingsutil.ErrInvalid) {
			t.Errorf("%s: Decode = %+v, %v; want ErrInvalid", tc.name, got, err)
		}
	}
}

// TestRemove checks Remove takes one account's file and RemoveAll takes the
// rest, and that neither minds there being nothing to remove.
func TestRemove(t *testing.T) {
	dataDir := t.TempDir()
	if result, err := usersettingsutil.Remove(usersettingsutil.RemoveParams{DataDir: dataDir, UserID: 1}); err != nil || result.Removed {
		t.Errorf("Remove with no file = %+v, %v", result, err)
	}
	for _, id := range []int64{1, 2} {
		if _, err := usersettingsutil.Save(usersettingsutil.SaveParams{
			DataDir: dataDir, UserID: id, Settings: usersettingsutil.Settings{ThemeColor: "teal"},
		}); err != nil {
			t.Fatal(err)
		}
	}
	if result, err := usersettingsutil.Remove(usersettingsutil.RemoveParams{DataDir: dataDir, UserID: 1}); err != nil || !result.Removed {
		t.Errorf("Remove = %+v, %v; want it removed", result, err)
	}
	if got, _ := usersettingsutil.Load(usersettingsutil.LoadParams{DataDir: dataDir, UserID: 1}); got.Settings.ThemeColor != "" {
		t.Error("account 1 still has settings after Remove")
	}
	if got, _ := usersettingsutil.Load(usersettingsutil.LoadParams{DataDir: dataDir, UserID: 2}); got.Settings.ThemeColor != "teal" {
		t.Error("Remove took another account's settings")
	}
	if err := usersettingsutil.RemoveAll(usersettingsutil.RemoveAllParams{DataDir: dataDir}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(usersettingsutil.Dir(dataDir)); !os.IsNotExist(err) {
		t.Errorf("the settings directory outlived RemoveAll (stat err %v)", err)
	}
}
