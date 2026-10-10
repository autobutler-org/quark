package usersettingsutil_test

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/notificationutil"
	"github.com/autobutler-org/quark/pkg/util/usersettingsutil"
)

// addUser makes an account, which a user_settings row needs, and returns its
// id.
func addUser(t *testing.T, queries *db.Queries, username string) int64 {
	t.Helper()
	user, err := queries.CreateUser(context.Background(), db.CreateUserParams{Username: username, PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser(%s): %v", username, err)
	}
	return user.ID
}

func save(t *testing.T, queries *db.Queries, userID int64, settings usersettingsutil.Settings) {
	t.Helper()
	saved, err := usersettingsutil.Save(context.Background(), usersettingsutil.SaveParams{Queries: queries, UserID: userID, Settings: settings})
	if err != nil || !reflect.DeepEqual(saved.Settings, settings) {
		t.Fatalf("Save(%d, %+v) = %+v, %v", userID, settings, saved, err)
	}
}

func load(t *testing.T, queries *db.Queries, userID int64) usersettingsutil.Settings {
	t.Helper()
	got, err := usersettingsutil.Load(context.Background(), usersettingsutil.LoadParams{Queries: queries, UserID: userID})
	if err != nil {
		t.Fatalf("Load(%d): %v", userID, err)
	}
	return got.Settings
}

// stored returns an account's row as it sits in the table, and whether it has
// one.
func stored(t *testing.T, queries *db.Queries, userID int64) (string, bool) {
	t.Helper()
	row, err := queries.GetUserSettings(context.Background(), userID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false
	}
	if err != nil {
		t.Fatal(err)
	}
	return row, true
}

// writeLegacy writes one file of the legacy user-settings directory.
func writeLegacy(t *testing.T, dataDir, name, content string) {
	t.Helper()
	dir := filepath.Join(dataDir, "user-settings")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

// TestSaveLoad_RoundTripPerAccount checks an account with no row reads as the
// zero settings, that a save is read back, that two accounts' settings are
// separate, and that clearing an override is a save like any other.
func TestSaveLoad_RoundTripPerAccount(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	first, second := addUser(t, queries, "first"), addUser(t, queries, "second")
	if got := load(t, queries, first); !reflect.DeepEqual(got, usersettingsutil.Settings{}) {
		t.Fatalf("Load with no row = %+v; want zero settings", got)
	}

	themeColors := map[int64]string{first: "teal", second: "#0ea5e9"}
	for id, themeColor := range themeColors {
		save(t, queries, id, usersettingsutil.Settings{ThemeColor: themeColor})
	}
	for id, themeColor := range themeColors {
		if got := load(t, queries, id); got.ThemeColor != themeColor {
			t.Errorf("Load(%d) = %+v; want theme color %q", id, got, themeColor)
		}
	}

	save(t, queries, first, usersettingsutil.Settings{})
	if got := load(t, queries, first); got.ThemeColor != "" {
		t.Errorf("theme color after clearing = %q", got.ThemeColor)
	}
}

// TestLoad_IgnoresUnknownFields checks a row a newer build wrote, with a
// field this one does not have, still loads.
func TestLoad_IgnoresUnknownFields(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	id := addUser(t, queries, "first")
	if err := queries.SetUserSettings(context.Background(), db.SetUserSettingsParams{UserID: id, Settings: `{"themeColor":"teal","fontSize":12}`}); err != nil {
		t.Fatal(err)
	}
	if got := load(t, queries, id); got.ThemeColor != "teal" {
		t.Errorf("Load = %+v; want theme color teal", got)
	}
}

// TestSave_RefusesInvalidThemeColor checks a malformed theme color is ErrInvalid and
// leaves the stored settings alone.
func TestSave_RefusesInvalidThemeColor(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	id := addUser(t, queries, "first")
	if _, err := usersettingsutil.Save(context.Background(), usersettingsutil.SaveParams{
		Queries: queries, UserID: id, Settings: usersettingsutil.Settings{ThemeColor: "#0EA5E9"},
	}); !errors.Is(err, usersettingsutil.ErrInvalid) {
		t.Errorf("Save with an uppercase color = %v, want ErrInvalid", err)
	}
	if row, ok := stored(t, queries, id); ok {
		t.Errorf("a refused save stored %s", row)
	}
}

// TestDisabledNotifications_RoundTrip checks the notification types an account
// turned off are stored and read back, that a save without them turns every
// type back on, and that an account that chose none stores no such field.
func TestDisabledNotifications_RoundTrip(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	id := addUser(t, queries, "first")
	disabled := []notificationutil.Type{notificationutil.TypeBackupStale, notificationutil.TypeBackupDue}
	save(t, queries, id, usersettingsutil.Settings{ThemeColor: "teal", DisabledNotifications: disabled})
	if got := load(t, queries, id); !reflect.DeepEqual(got.DisabledNotifications, disabled) || got.ThemeColor != "teal" {
		t.Fatalf("Load = %+v; want %v disabled and theme color teal", got, disabled)
	}

	save(t, queries, id, usersettingsutil.Settings{ThemeColor: "teal"})
	if got := load(t, queries, id); len(got.DisabledNotifications) != 0 {
		t.Errorf("Load after a save without them = %+v; want every type on", got)
	}
	if row, _ := stored(t, queries, id); strings.Contains(row, "disabledNotifications") {
		t.Errorf("the stored settings carry an empty disabledNotifications: %s", row)
	}
}

// TestSave_RefusesInvalidNotificationTypes checks an unknown or repeated
// notification type is ErrInvalid and stores nothing.
func TestSave_RefusesInvalidNotificationTypes(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	id := addUser(t, queries, "first")
	for name, disabled := range map[string][]notificationutil.Type{
		"unknown":  {"backup_complete"},
		"empty":    {""},
		"repeated": {notificationutil.TypeBackupDue, notificationutil.TypeBackupDue},
	} {
		if _, err := usersettingsutil.Save(context.Background(), usersettingsutil.SaveParams{
			Queries: queries, UserID: id, Settings: usersettingsutil.Settings{DisabledNotifications: disabled},
		}); !errors.Is(err, usersettingsutil.ErrInvalid) {
			t.Errorf("%s: Save = %v, want ErrInvalid", name, err)
		}
		if row, ok := stored(t, queries, id); ok {
			t.Errorf("%s: a refused save stored %s", name, row)
		}
	}
}

// TestDecode_DisabledNotifications checks a body may list known notification
// types once each, and that anything else is ErrInvalid.
func TestDecode_DisabledNotifications(t *testing.T) {
	for _, tc := range []struct {
		name, body string
		want       []notificationutil.Type
		valid      bool
	}{
		{"one type", `{"disabledNotifications":["backup_due"]}`, []notificationutil.Type{notificationutil.TypeBackupDue}, true},
		{
			"every type", `{"themeColor":"teal","disabledNotifications":["backup_due","backup_stale"]}`,
			[]notificationutil.Type{notificationutil.TypeBackupDue, notificationutil.TypeBackupStale}, true,
		},
		{"empty list", `{"disabledNotifications":[]}`, []notificationutil.Type{}, true},
		{"null", `{"disabledNotifications":null}`, nil, true},
		{"unknown type", `{"disabledNotifications":["backup_complete"]}`, nil, false},
		{"repeated type", `{"disabledNotifications":["backup_due","backup_due"]}`, nil, false},
		{"not a list", `{"disabledNotifications":"backup_due"}`, nil, false},
		{"not strings", `{"disabledNotifications":[1]}`, nil, false},
	} {
		got, err := usersettingsutil.Decode(strings.NewReader(tc.body))
		if tc.valid && (err != nil || !reflect.DeepEqual(got.DisabledNotifications, tc.want)) {
			t.Errorf("%s: Decode = %+v, %v; want %v disabled", tc.name, got, err, tc.want)
		}
		if !tc.valid && !errors.Is(err, usersettingsutil.ErrInvalid) {
			t.Errorf("%s: Decode = %+v, %v; want ErrInvalid", tc.name, got, err)
		}
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

// TestDeleteUser_TakesItsSettings checks an account's settings go with the
// account and nobody else's do, so an id SQLite hands out again starts with
// none (#2740). The foreign key does it; nothing calls a remove.
func TestDeleteUser_TakesItsSettings(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	first, second := addUser(t, queries, "first"), addUser(t, queries, "second")
	for _, id := range []int64{first, second} {
		save(t, queries, id, usersettingsutil.Settings{ThemeColor: "teal"})
	}
	if err := queries.DeleteUser(context.Background(), first); err != nil {
		t.Fatal(err)
	}
	if row, ok := stored(t, queries, first); ok {
		t.Errorf("the deleted account still has settings: %s", row)
	}
	if got := load(t, queries, second); got.ThemeColor != "teal" {
		t.Error("deleting one account took another's settings")
	}
}

// TestImport_MovesTheFilesIntoTheDatabase checks each legacy file lands on its
// account, that settings already in the database win, that a file for an
// account that is gone, a damaged file and an oversized one are skipped
// without failing the rest, that the directory is renamed, and that importing
// again adds nothing.
func TestImport_MovesTheFilesIntoTheDatabase(t *testing.T) {
	queries := dbtest.NewDB(t).Queries
	fromFile, alreadySaved, damaged, oversized := addUser(t, queries, "a"), addUser(t, queries, "b"), addUser(t, queries, "c"), addUser(t, queries, "d")
	const gone int64 = 9999
	dataDir := t.TempDir()
	name := func(id int64) string { return strconv.FormatInt(id, 10) + ".json" }
	writeLegacy(t, dataDir, name(fromFile), `{"themeColor":"teal","disabledNotifications":["backup_due"],"fontSize":12}`)
	writeLegacy(t, dataDir, name(alreadySaved), `{"themeColor":"teal"}`)
	writeLegacy(t, dataDir, name(gone), `{"themeColor":"teal"}`)
	writeLegacy(t, dataDir, name(damaged), `{not json`)
	writeLegacy(t, dataDir, name(oversized), `{"themeColor":"`+strings.Repeat("a", int(usersettingsutil.MaxRequestBytes))+`"}`)
	writeLegacy(t, dataDir, "notes.txt", "not a settings file")
	save(t, queries, alreadySaved, usersettingsutil.Settings{ThemeColor: "#112233"})

	runImport := func() int {
		t.Helper()
		result, err := usersettingsutil.Import(context.Background(), usersettingsutil.ImportParams{Queries: queries, DataDir: dataDir})
		if err != nil {
			t.Fatalf("Import: %v", err)
		}
		return result.Files
	}
	if n := runImport(); n != 3 {
		t.Errorf("Import read %d files, want 3", n)
	}

	want := usersettingsutil.Settings{ThemeColor: "teal", DisabledNotifications: []notificationutil.Type{notificationutil.TypeBackupDue}}
	if got := load(t, queries, fromFile); !reflect.DeepEqual(got, want) {
		t.Errorf("imported settings = %+v, want %+v", got, want)
	}
	if got := load(t, queries, alreadySaved); got.ThemeColor != "#112233" {
		t.Errorf("Import replaced settings already in the database with %+v", got)
	}
	for label, id := range map[string]int64{"gone": gone, "damaged": damaged, "oversized": oversized} {
		if row, ok := stored(t, queries, id); ok {
			t.Errorf("the %s file was imported as %s", label, row)
		}
	}
	dir := filepath.Join(dataDir, "user-settings")
	if _, err := os.Stat(dir); !os.IsNotExist(err) {
		t.Errorf("the legacy directory is still there (stat err %v)", err)
	}
	if _, err := os.Stat(dir + ".imported"); err != nil {
		t.Errorf("the legacy directory was not renamed: %v", err)
	}

	if n := runImport(); n != 0 {
		t.Errorf("a second Import read %d files, want 0", n)
	}
	if got := load(t, queries, fromFile); !reflect.DeepEqual(got, want) {
		t.Errorf("settings after a second Import = %+v, want %+v", got, want)
	}
}

// TestImport_NoDirectoryIsNothingToDo checks a Quark with no legacy directory
// imports nothing and is not an error.
func TestImport_NoDirectoryIsNothingToDo(t *testing.T) {
	result, err := usersettingsutil.Import(context.Background(), usersettingsutil.ImportParams{Queries: dbtest.NewDB(t).Queries, DataDir: t.TempDir()})
	if err != nil || result.Files != 0 {
		t.Errorf("Import with no directory = %+v, %v", result, err)
	}
}

// TestSave_TwoInstancesShareSettings checks settings saved through one handle
// on a database are loaded through another, as two server instances on one
// database would, and that the later save wins on both.
func TestSave_TwoInstancesShareSettings(t *testing.T) {
	path := filepath.Join(t.TempDir(), "quark.db")
	open := func() *sql.DB {
		sqlDB, err := sql.Open("sqlite", db.DSN(path))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { sqlDB.Close() })
		return sqlDB
	}
	firstDB, secondDB := open(), open()
	first, second := db.New(firstDB), db.New(secondDB)
	if err := db.ResetDatabase(&db.DatabaseSqlc{Db: firstDB, Queries: first}); err != nil {
		t.Fatal(err)
	}
	id := addUser(t, first, "first")

	save(t, first, id, usersettingsutil.Settings{ThemeColor: "teal"})
	if got := load(t, second, id); got.ThemeColor != "teal" {
		t.Errorf("the second instance loads %+v, want theme color teal", got)
	}
	save(t, second, id, usersettingsutil.Settings{ThemeColor: "#112233"})
	if got := load(t, first, id); got.ThemeColor != "#112233" {
		t.Errorf("the first instance loads %+v, want theme color #112233", got)
	}
}
