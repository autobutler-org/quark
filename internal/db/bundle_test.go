package db_test

import (
	"context"
	"database/sql"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// bundleSeed is a little of everything a bundle must carry: accounts, a
// self-referencing album, a blob, a flag, and derived content-search text.
var bundleSeed = []string{
	`INSERT INTO users (id, username, password_hash, recovery_phrase_hash, is_admin, created_at)
		VALUES (7, 'ada', 'p', 'r', 1, '2026-01-02 03:04:05')`,
	`INSERT INTO sessions (token, user_id, expires_at) VALUES ('t1', 7, '2026-12-31 23:59:59')`,
	`INSERT INTO photo_albums (id, name, user_id) VALUES (5, 'trips', 7)`,
	`INSERT INTO photo_albums (id, name, parent_id, user_id) VALUES (3, 'paris', 5, 7)`,
	`INSERT INTO vault_keys (user_id, wrapped_by_password, salt_pw, wrapped_by_phrase, salt_rp, kdf_params)
		VALUES (7, x'00ff10', x'01', x'', x'01', '{}')`,
	`INSERT INTO photo_hashes (device_serial, rel_path, taken_checked) VALUES ('', 'a.jpg', 1)`,
	`INSERT INTO group_members (group_id, user_id) SELECT id, 7 FROM groups WHERE name = 'everyone'`,
	`INSERT INTO file_content (serial, rel_path, extracted) VALUES ('', 'a.txt', 'hello')`,
}

// bundleRows reads back what bundleSeed wrote, the same on either engine.
func bundleRows(t *testing.T, sqlDB *sql.DB) string {
	t.Helper()
	var username, wrapped, empty, installID string
	var isAdmin, albums, content int64
	var parent sql.NullInt64
	queries := []struct {
		query string
		dest  []any
	}{
		{`SELECT username, is_admin FROM users WHERE id = 7`, []any{&username, &isAdmin}},
		{`SELECT encode(wrapped_by_password, 'hex'), encode(wrapped_by_phrase, 'hex') FROM vault_keys WHERE user_id = 7`, []any{&wrapped, &empty}},
		{`SELECT COUNT(*) FROM photo_albums`, []any{&albums}},
		{`SELECT parent_id FROM photo_albums WHERE id = 3`, []any{&parent}},
		{`SELECT COUNT(*) FROM file_content`, []any{&content}},
		{`SELECT install_id FROM install`, []any{&installID}},
	}
	if db.BackendOf(sqlDB) == db.SQLite {
		queries[1].query = `SELECT hex(wrapped_by_password), hex(wrapped_by_phrase) FROM vault_keys WHERE user_id = 7`
	}
	for _, q := range queries {
		if err := sqlDB.QueryRow(q.query).Scan(q.dest...); err != nil {
			t.Fatalf("%s: %v", q.query, err)
		}
	}
	return fmt.Sprint(username, strings.ToLower(wrapped), "["+empty+"]", installID, isAdmin, albums, parent.Int64, content)
}

func export(t *testing.T, params db.ExportDatabaseParams) string {
	t.Helper()
	params.Dest = filepath.Join(t.TempDir(), "bundle.db")
	if _, err := db.ExportDatabase(context.Background(), params); err != nil {
		t.Fatalf("ExportDatabase: %v", err)
	}
	return params.Dest
}

func TestBundle_SQLiteToSQLite(t *testing.T) {
	source := sqliteFileForMove(t, bundleSeed...)
	contents, modTime := fileState(t, source)
	bundle := export(t, db.ExportDatabaseParams{Source: db.Config{Backend: db.SQLite}, SQLitePath: source})
	requireUnchanged(t, source, contents, modTime)

	sourceDB, err := sql.Open("sqlite", db.DSN(source))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { sourceDB.Close() })
	want := bundleRows(t, sourceDB)
	// file_content is rebuilt, not copied.
	want = want[:len(want)-1] + "0"

	target := filepath.Join(t.TempDir(), "quark.db")
	params := db.ImportDatabaseParams{BundleDB: bundle, Target: db.Config{Backend: db.SQLite}, SQLitePath: target}
	result, err := db.ImportDatabase(context.Background(), params)
	if err != nil {
		t.Fatalf("ImportDatabase: %v", err)
	}
	counts := map[string]int64{}
	for _, table := range result.Tables {
		counts[table.Table] = table.Rows
	}
	if counts["users"] != 1 || counts["photo_albums"] != 2 || counts["install"] != 1 || counts["groups"] != 1 {
		t.Errorf("imported counts = %v", counts)
	}
	targetDB, err := sql.Open("sqlite", db.DSN(target))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { targetDB.Close() })
	if got := bundleRows(t, targetDB); got != want {
		t.Errorf("rows after the import = %q, want %q", got, want)
	}

	// The install is in use now: a second import is refused and changes nothing.
	contents, modTime = fileState(t, target)
	if _, err := db.ImportDatabase(context.Background(), params); err == nil || !strings.Contains(err.Error(), "already has 1 account") {
		t.Fatalf("second ImportDatabase = %v, want a refusal", err)
	}
	requireUnchanged(t, target, contents, modTime)
}

func TestBundle_ExportRefusesAnOlderSchema(t *testing.T) {
	source := sqliteFileForMove(t, `UPDATE schema_migrations SET version = version - 1`)
	_, err := db.ExportDatabase(context.Background(), db.ExportDatabaseParams{
		Source: db.Config{Backend: db.SQLite}, SQLitePath: source, Dest: filepath.Join(t.TempDir(), "b.db"),
	})
	if err == nil || !strings.Contains(err.Error(), "Start this build of Quark on SQLite once") {
		t.Fatalf("ExportDatabase on an older schema = %v, want a refusal", err)
	}
}

// TestBundle_EveryDirection carries one install through all four directions:
// SQLite to PostgreSQL, PostgreSQL to PostgreSQL, PostgreSQL to SQLite, and
// (in TestBundle_SQLiteToSQLite) SQLite to SQLite.
func TestBundle_EveryDirection(t *testing.T) {
	firstURL := dbtest.PostgresURL(t)
	secondURL := dbtest.PostgresURL(t)
	source := sqliteFileForMove(t, bundleSeed...)
	sourceDB, err := sql.Open("sqlite", db.DSN(source))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { sourceDB.Close() })
	want := bundleRows(t, sourceDB)
	want = want[:len(want)-1] + "0"
	ctx := context.Background()

	fromSQLite := export(t, db.ExportDatabaseParams{Source: db.Config{Backend: db.SQLite}, SQLitePath: source})
	first := db.Config{Backend: db.Postgres, PostgresURL: firstURL}
	if _, err := db.ImportDatabase(ctx, db.ImportDatabaseParams{BundleDB: fromSQLite, Target: first}); err != nil {
		t.Fatalf("SQLite to PostgreSQL: %v", err)
	}

	fromPostgres := export(t, db.ExportDatabaseParams{Source: first})
	second := db.Config{Backend: db.Postgres, PostgresURL: secondURL}
	if _, err := db.ImportDatabase(ctx, db.ImportDatabaseParams{BundleDB: fromPostgres, Target: second}); err != nil {
		t.Fatalf("PostgreSQL to PostgreSQL: %v", err)
	}
	secondDB, err := db.ConnectToPostgres(secondURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { secondDB.Db.Close() })
	if got := bundleRows(t, secondDB.Db); got != want {
		t.Errorf("rows on PostgreSQL = %q, want %q", got, want)
	}

	fromPostgres = export(t, db.ExportDatabaseParams{Source: second})
	target := filepath.Join(t.TempDir(), "quark.db")
	if _, err := db.ImportDatabase(ctx, db.ImportDatabaseParams{
		BundleDB: fromPostgres, Target: db.Config{Backend: db.SQLite}, SQLitePath: target,
	}); err != nil {
		t.Fatalf("PostgreSQL to SQLite: %v", err)
	}
	targetDB, err := sql.Open("sqlite", db.DSN(target))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { targetDB.Close() })
	if got := bundleRows(t, targetDB); got != want {
		t.Errorf("rows on SQLite after PostgreSQL = %q, want %q", got, want)
	}
	var createdAt string
	if err := targetDB.QueryRow(`SELECT created_at FROM users WHERE id = 7`).Scan(&createdAt); err != nil ||
		!strings.HasPrefix(createdAt, "2026-01-02") {
		t.Errorf("created_at after the round trip = %q, %v", createdAt, err)
	}
}
