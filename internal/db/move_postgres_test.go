package db_test

import (
	"bytes"
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// sqliteFileForMove returns a migrated SQLite database with seed run against
// it, closed, and the path to its file.
func sqliteFileForMove(t *testing.T, seed ...string) string {
	t.Helper()
	database := dbtest.NewDB(t)
	var path string
	if err := database.Db.QueryRow(`SELECT file FROM pragma_database_list WHERE name = 'main'`).Scan(&path); err != nil {
		t.Fatal(err)
	}
	for _, statement := range seed {
		if _, err := database.Db.Exec(statement); err != nil {
			t.Fatalf("%s: %v", statement, err)
		}
	}
	if err := database.Db.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}

// fileState is what MoveToPostgres must leave alone: the bytes and the mtime.
func fileState(t *testing.T, path string) ([]byte, time.Time) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return contents, info.ModTime()
}

func requireUnchanged(t *testing.T, path string, contents []byte, modTime time.Time) {
	t.Helper()
	gotContents, gotModTime := fileState(t, path)
	if !bytes.Equal(gotContents, contents) || !gotModTime.Equal(modTime) {
		t.Fatalf("MoveToPostgres changed %s", path)
	}
}

func TestMoveToPostgres_RefusesAMissingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "quark.db")
	_, err := db.MoveToPostgres(context.Background(), db.MoveToPostgresParams{SQLitePath: path, PostgresURL: "postgres://x"})
	if err == nil || !strings.Contains(err.Error(), "--sqlite") {
		t.Fatalf("MoveToPostgres on a missing file = %v, want an error naming --sqlite", err)
	}
	if _, statErr := os.Stat(path); !os.IsNotExist(statErr) {
		t.Fatalf("MoveToPostgres created %s", path)
	}
}

func TestMoveToPostgres_RefusesAnOlderSQLiteSchema(t *testing.T) {
	path := sqliteFileForMove(t, `UPDATE schema_migrations SET version = version - 1`)
	contents, modTime := fileState(t, path)
	_, err := db.MoveToPostgres(context.Background(), db.MoveToPostgresParams{SQLitePath: path, PostgresURL: "postgres://x"})
	if err == nil || !strings.Contains(err.Error(), "Start this build of Quark on SQLite once") {
		t.Fatalf("MoveToPostgres on an older schema = %v, want a refusal saying to start on SQLite first", err)
	}
	requireUnchanged(t, path, contents, modTime)
}

func TestMoveToPostgres_CopiesEveryRow(t *testing.T) {
	databaseURL := dbtest.PostgresURL(t)
	path := sqliteFileForMove(t,
		`INSERT INTO users (id, username, password_hash, recovery_phrase_hash, is_admin, created_at)
			VALUES (7, 'ada', 'p', 'r', 1, '2026-01-02 03:04:05')`,
		`INSERT INTO sessions (token, user_id, expires_at) VALUES ('t1', 7, '2026-12-31 23:59:59')`,
		`INSERT INTO photo_albums (id, name, user_id) VALUES (5, 'trips', 7)`,
		// A child whose id is lower than its parent's.
		`INSERT INTO photo_albums (id, name, parent_id, user_id) VALUES (3, 'paris', 5, 7)`,
		`INSERT INTO vault_keys (user_id, wrapped_by_password, salt_pw, kdf_params) VALUES (7, x'00ff10', x'01', '{}')`,
		`INSERT INTO photo_hashes (device_serial, rel_path, taken_checked) VALUES ('', 'a.jpg', 1)`,
		`INSERT INTO group_members (group_id, user_id) SELECT id, 7 FROM groups WHERE name = 'everyone'`,
		`INSERT INTO file_content (serial, rel_path, extracted) VALUES ('', 'a.txt', 'hello')`,
	)
	contents, modTime := fileState(t, path)
	result, err := db.MoveToPostgres(context.Background(), db.MoveToPostgresParams{SQLitePath: path, PostgresURL: databaseURL})
	if err != nil {
		t.Fatalf("MoveToPostgres: %v", err)
	}
	requireUnchanged(t, path, contents, modTime)

	counts := map[string]int64{}
	for _, table := range result.Tables {
		counts[table.Table] = table.Rows
	}
	for table, want := range map[string]int64{
		"users": 1, "sessions": 1, "photo_albums": 2, "vault_keys": 1, "photo_hashes": 1,
		"group_members": 1, "groups": 1, "install": 1, "file_content": 0,
	} {
		if counts[table] != want {
			t.Errorf("%s: moved %d rows, want %d", table, counts[table], want)
		}
	}

	target, err := db.ConnectToPostgres(databaseURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { target.Db.Close() })

	var createdAt time.Time
	var isAdmin int64
	if err := target.Db.QueryRow(`SELECT created_at, is_admin FROM users WHERE id = 7`).Scan(&createdAt, &isAdmin); err != nil {
		t.Fatal(err)
	}
	if want := time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC); !createdAt.Equal(want) || isAdmin != 1 {
		t.Errorf("users row = %v, %d; want %v, 1", createdAt, isAdmin, want)
	}
	var wrapped []byte
	if err := target.Db.QueryRow(`SELECT wrapped_by_password FROM vault_keys WHERE user_id = 7`).Scan(&wrapped); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(wrapped, []byte{0x00, 0xff, 0x10}) {
		t.Errorf("vault_keys.wrapped_by_password = %x, want 00ff10", wrapped)
	}
	var takenChecked bool
	if err := target.Db.QueryRow(`SELECT taken_checked FROM photo_hashes`).Scan(&takenChecked); err != nil || !takenChecked {
		t.Errorf("photo_hashes.taken_checked = %v, %v; want true", takenChecked, err)
	}

	sqliteDB, err := sql.Open("sqlite", db.DSN("file:"+path+"?mode=ro"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { sqliteDB.Close() })
	var sqliteInstall, postgresInstall string
	if err := sqliteDB.QueryRow(`SELECT install_id FROM install`).Scan(&sqliteInstall); err != nil {
		t.Fatal(err)
	}
	if err := target.Db.QueryRow(`SELECT install_id FROM install`).Scan(&postgresInstall); err != nil {
		t.Fatal(err)
	}
	if sqliteInstall != postgresInstall {
		t.Errorf("install id = %q on PostgreSQL, want SQLite's %q", postgresInstall, sqliteInstall)
	}

	// The identity sequence is past the copied ids, so the next insert works.
	var nextID int64
	if err := target.Db.QueryRow(
		`INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES ('bob', 'p', 'r') RETURNING id`,
	).Scan(&nextID); err != nil || nextID <= 7 {
		t.Fatalf("insert after the move = %d, %v; want an id past 7", nextID, err)
	}

	// The database is in use now, so a second run is refused and changes nothing.
	if _, err := db.MoveToPostgres(context.Background(), db.MoveToPostgresParams{SQLitePath: path, PostgresURL: databaseURL}); err == nil ||
		!strings.Contains(err.Error(), "already has") {
		t.Fatalf("second MoveToPostgres = %v, want a refusal", err)
	}
	var users int64
	if err := target.Db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&users); err != nil || users != 2 {
		t.Fatalf("users after the refused run = %d, %v; want 2", users, err)
	}
}
