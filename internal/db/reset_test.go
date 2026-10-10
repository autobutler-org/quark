package db

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	_ "modernc.org/sqlite"
)

// Two instances serving one install are two processes holding their own
// handles on one database. Two *sql.DB on one file is that, as far as SQLite's
// locking goes, and it is what these tests mean by "instance" until the
// two-instance harness (#2971) exists.

// openInstance opens another handle on the database at path.
func openInstance(t *testing.T, path string) *DatabaseSqlc {
	t.Helper()
	sqlDB, err := sql.Open("sqlite", DSN(path))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	t.Cleanup(func() { sqlDB.Close() })
	return &DatabaseSqlc{Db: sqlDB, Queries: New(sqlDB)}
}

// schemaOf lists every object in sqlite_master with the SQL that made it.
func schemaOf(t *testing.T, sqlDB *sql.DB) []string {
	t.Helper()
	rows, err := sqlDB.Query(`SELECT type, name, COALESCE(sql, '') FROM sqlite_master ORDER BY type, name`)
	if err != nil {
		t.Fatalf("read schema: %v", err)
	}
	defer rows.Close()
	var objects []string
	for rows.Next() {
		var kind, name, body string
		if err := rows.Scan(&kind, &name, &body); err != nil {
			t.Fatalf("scan schema: %v", err)
		}
		objects = append(objects, kind+" "+name+": "+body)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("read schema: %v", err)
	}
	return objects
}

// A second instance must never see the reset half done (#3085). Dropping the
// tables one statement at a time and migrating afterwards left a window in
// which its queries failed with "no such table".
func TestResetDatabase_IsAtomicToASecondInstance(t *testing.T) {
	path := filepath.Join(t.TempDir(), "quark.db")
	resetting := openInstance(t, path)
	if err := ResetDatabase(resetting); err != nil {
		t.Fatalf("initial migrate: %v", err)
	}
	serving := openInstance(t, path)

	stop := make(chan struct{})
	missing := make(chan error, 1)
	go func() {
		defer close(missing)
		for {
			select {
			case <-stop:
				return
			default:
			}
			var rows int
			// install comes from the last migration, so it is the table
			// missing longest. Waiting out the reset and giving up busy is
			// fine; a schema with holes in it is not.
			err := serving.Db.QueryRow(`SELECT COUNT(*) FROM install`).Scan(&rows)
			if err != nil && strings.Contains(err.Error(), "no such table") {
				missing <- err
				return
			}
		}
	}()

	for range 5 {
		if err := ResetDatabase(resetting); err != nil {
			t.Fatalf("reset: %v", err)
		}
	}
	close(stop)
	if err := <-missing; err != nil {
		t.Fatalf("the second instance saw a half-reset database: %v", err)
	}
}

// ResetDatabase applies the migrations itself, inside its transaction, so it
// has to leave exactly what golang-migrate leaves, recorded version included.
func TestResetDatabase_LeavesTheSchemaMigrationsBuild(t *testing.T) {
	migrated := openInstance(t, filepath.Join(t.TempDir(), "migrated.db"))
	if err := initSchema(migrated); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	reset := openInstance(t, filepath.Join(t.TempDir(), "reset.db"))
	if err := ResetDatabase(reset); err != nil {
		t.Fatalf("reset: %v", err)
	}

	want, got := schemaOf(t, migrated.Db), schemaOf(t, reset.Db)
	if strings.Join(want, "\n") != strings.Join(got, "\n") {
		t.Fatalf("reset schema differs from the migrated one\nmigrated:\n%s\nreset:\n%s",
			strings.Join(want, "\n"), strings.Join(got, "\n"))
	}

	var wantVersion, gotVersion int
	var wantDirty, gotDirty bool
	const recorded = `SELECT version, dirty FROM schema_migrations`
	if err := migrated.Db.QueryRow(recorded).Scan(&wantVersion, &wantDirty); err != nil {
		t.Fatalf("read migrated version: %v", err)
	}
	if err := reset.Db.QueryRow(recorded).Scan(&gotVersion, &gotDirty); err != nil {
		t.Fatalf("read reset version: %v", err)
	}
	if gotVersion != wantVersion || gotDirty != wantDirty {
		t.Fatalf("reset recorded version %d dirty=%v, migrations record %d dirty=%v",
			gotVersion, gotDirty, wantVersion, wantDirty)
	}

	// The next boot runs the migrations over it and must find nothing to do.
	if err := initSchema(reset); err != nil {
		t.Fatalf("migrate after reset: %v", err)
	}
}

// The install id is how an instance learns the install it booted on is gone,
// so every reset has to issue a new one.
func TestResetDatabase_IssuesANewInstallID(t *testing.T) {
	path := filepath.Join(t.TempDir(), "quark.db")
	resetting := openInstance(t, path)
	if err := ResetDatabase(resetting); err != nil {
		t.Fatalf("initial migrate: %v", err)
	}
	other := openInstance(t, path)

	before, err := other.Queries.GetInstallID(t.Context())
	if err != nil {
		t.Fatalf("read install id: %v", err)
	}
	if before == "" {
		t.Fatal("a fresh install has no install id")
	}
	if err := ResetDatabase(resetting); err != nil {
		t.Fatalf("reset: %v", err)
	}
	after, err := other.Queries.GetInstallID(t.Context())
	if err != nil {
		t.Fatalf("read install id after reset: %v", err)
	}
	if after == before {
		t.Fatalf("install id %q survived the reset", before)
	}
}
