package db

import (
	"database/sql"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

// The migration set was regrouped by subject area in #1758, which renumbered it
// from 000-021 down to 001-007. Every database built before that carries a
// version stamp from the old numbering, and initSchema has to notice: the high
// stamps stop golang-migrate dead, and the low ones collide with the new
// numbers and would otherwise be half-migrated in silence.
//
// These tests cannot use the dbtest helper - it lives in a package that imports
// this one, and initSchema is unexported - so they open their databases the way
// migrations_test.go does.

// legacySchemaAtVersion21 is the shape a developer's quark.db had at the top of
// the old numbering: auth with is_admin (old 016), sessions with last_used_at
// (old 020), device_names still keyed by device_path, and an FTS5 table (old
// 019) whose shadow tables the drop has to cope with.
const legacySchemaAtVersion21 = `
CREATE TABLE users (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	username TEXT NOT NULL UNIQUE,
	password_hash TEXT NOT NULL,
	recovery_phrase_hash TEXT NOT NULL,
	created_at DATETIME NOT NULL DEFAULT (datetime('now')),
	is_admin INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE sessions (
	token TEXT PRIMARY KEY,
	user_id INTEGER NOT NULL,
	expires_at DATETIME NOT NULL,
	created_at DATETIME NOT NULL DEFAULT (datetime('now')),
	last_used_at DATETIME NOT NULL DEFAULT (datetime('now')),
	FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE TABLE device_names (
	device_path TEXT PRIMARY KEY,
	display_name TEXT NOT NULL,
	updated_at DATETIME NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE connected_devices (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	ip_address TEXT NOT NULL,
	user_agent TEXT NOT NULL DEFAULT '',
	UNIQUE (ip_address, user_agent)
);
CREATE VIRTUAL TABLE file_content_fts USING fts5(content);
`

// legacySchemaAtVersion3 is the same database eighteen migrations earlier, and
// the dangerous one: old 3 is a number the new set can serve. Old 002 had
// already created users, so the table is present - only is_admin,
// last_used_at and device_roles are missing.
const legacySchemaAtVersion3 = `
CREATE TABLE users (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	username TEXT NOT NULL UNIQUE,
	password_hash TEXT NOT NULL,
	recovery_phrase_hash TEXT NOT NULL,
	created_at DATETIME NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE sessions (
	token TEXT PRIMARY KEY,
	user_id INTEGER NOT NULL,
	expires_at DATETIME NOT NULL,
	created_at DATETIME NOT NULL DEFAULT (datetime('now')),
	FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE TABLE device_names (
	device_path TEXT PRIMARY KEY,
	display_name TEXT NOT NULL,
	updated_at DATETIME NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE connected_devices (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	ip_address TEXT NOT NULL,
	user_agent TEXT NOT NULL DEFAULT '',
	UNIQUE (ip_address, user_agent)
);
`

func openSchemaTestDB(t *testing.T) *sql.DB {
	t.Helper()
	conn, err := sql.Open("sqlite", DSN(filepath.Join(t.TempDir(), "quark.db")))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

// stampSchemaVersion writes the row golang-migrate would have written, in the
// table shape its sqlite driver creates.
func stampSchemaVersion(t *testing.T, conn *sql.DB, version int, dirty bool) {
	t.Helper()
	statements := []string{
		`CREATE TABLE IF NOT EXISTS schema_migrations (version uint64, dirty bool)`,
		`DELETE FROM schema_migrations`,
	}
	for _, statement := range statements {
		if _, err := conn.Exec(statement); err != nil {
			t.Fatalf("stamp %q: %v", statement, err)
		}
	}
	if _, err := conn.Exec(
		`INSERT INTO schema_migrations (version, dirty) VALUES (?, ?)`, version, dirty,
	); err != nil {
		t.Fatalf("stamp version: %v", err)
	}
}

func readSchemaVersion(t *testing.T, conn *sql.DB) (int, bool) {
	t.Helper()
	var version int
	var dirty bool
	if err := conn.QueryRow(`SELECT version, dirty FROM schema_migrations`).Scan(&version, &dirty); err != nil {
		t.Fatalf("read schema_migrations: %v", err)
	}
	return version, dirty
}

// latestSchemaVersion is read off a freshly migrated database rather than
// written down here, so regrouping the set again does not break these tests -
// which is the whole reason the regrouping needed recovery code in the first
// place.
func latestSchemaVersion(t *testing.T) int {
	t.Helper()
	conn := openSchemaTestDB(t)
	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("migrate reference database: %v", err)
	}
	version, dirty := readSchemaVersion(t, conn)
	if dirty {
		t.Fatal("reference database came out dirty")
	}
	return version
}

func hasTable(t *testing.T, conn *sql.DB, table string) bool {
	t.Helper()
	var count int
	if err := conn.QueryRow(
		`SELECT COUNT(*) FROM sqlite_master WHERE name = ?`, table,
	).Scan(&count); err != nil {
		t.Fatalf("look up %s: %v", table, err)
	}
	return count > 0
}

func hasColumn(t *testing.T, conn *sql.DB, table, column string) bool {
	t.Helper()
	var count int
	if err := conn.QueryRow(
		`SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?`, table, column,
	).Scan(&count); err != nil {
		t.Fatalf("inspect %s.%s: %v", table, column, err)
	}
	return count > 0
}

// assertNewSchema checks the markers that only the compressed set produces:
// device_names re-keyed by serial, the device_roles table that the old
// numbering did not have until 008, and the is_admin column it did not have
// until 016.
func assertNewSchema(t *testing.T, conn *sql.DB) {
	t.Helper()
	version, dirty := readSchemaVersion(t, conn)
	if want := latestSchemaVersion(t); version != want {
		t.Errorf("schema version = %d, want %d", version, want)
	}
	if dirty {
		t.Error("recovery left the database dirty")
	}
	if !hasColumn(t, conn, "device_names", "device_serial") {
		t.Error("device_names is not keyed by device_serial; the old schema survived")
	}
	if hasColumn(t, conn, "device_names", "device_path") {
		t.Error("device_names still has device_path; the old schema survived")
	}
	if !hasTable(t, conn, "device_roles") {
		t.Error("device_roles missing; 002_storage_devices did not run")
	}
	if !hasColumn(t, conn, "users", "is_admin") {
		t.Error("users.is_admin missing; 001_auth did not run")
	}
	if !hasTable(t, conn, "vfs_metadata") {
		t.Error("vfs_metadata missing; 007_vfs did not run")
	}
}

func applySchema(t *testing.T, conn *sql.DB, schema string) {
	t.Helper()
	if _, err := conn.Exec(schema); err != nil {
		t.Fatalf("apply fixture schema: %v", err)
	}
}

// A stamp above the top of the migration set - a pre-#1758 database, or one a
// newer build migrated before a downgrade - is refused outright by
// golang-migrate, and the error travels out through ConnectToDatabase, so
// without this recovery the server could not start at all. The stamp is one
// past the top rather than a fixed number, because the set keeps growing and a
// fixed stamp eventually becomes a version the set can serve.
func TestInitSchemaRecoversFromVersionAboveTheMigrationSet(t *testing.T) {
	conn := openSchemaTestDB(t)
	applySchema(t, conn, legacySchemaAtVersion21)
	if _, err := conn.Exec(
		`INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES ('ada', 'x', 'y')`,
	); err != nil {
		t.Fatalf("seed legacy user: %v", err)
	}
	stampSchemaVersion(t, conn, latestSchemaVersion(t)+1, false)

	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("initSchema on a legacy database: %v", err)
	}

	assertNewSchema(t, conn)
	var users int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&users); err != nil {
		t.Fatalf("count users: %v", err)
	}
	if users != 0 {
		t.Errorf("legacy rows survived the rebuild: %d users", users)
	}
}

// The one that matters. Old 3 is a number the compressed set can serve, so the
// version alone says nothing is wrong - golang-migrate would apply 004 onward
// onto a schema with no device_roles, no users.is_admin and no
// sessions.last_used_at, and report success. The structural check is what catches it.
func TestInitSchemaRecoversFromOldVersionCollidingWithNewNumbering(t *testing.T) {
	conn := openSchemaTestDB(t)
	applySchema(t, conn, legacySchemaAtVersion3)
	stampSchemaVersion(t, conn, 3, false)

	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("initSchema on an old-numbering database: %v", err)
	}

	// Every one of these fails if the database was half-migrated instead of
	// rebuilt: the version reaches the top of the set either way.
	assertNewSchema(t, conn)
}

// A migration that died half-applied leaves a schema matching neither the
// version below it nor the one above, so the same recovery applies.
func TestInitSchemaRecoversFromDirtyDatabase(t *testing.T) {
	conn := openSchemaTestDB(t)
	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("initial migrate: %v", err)
	}
	stampSchemaVersion(t, conn, latestSchemaVersion(t), true)

	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("initSchema on a dirty database: %v", err)
	}
	assertNewSchema(t, conn)
}

// A first install has nothing recorded, and must migrate up rather than be
// treated as stale.
func TestInitSchemaMigratesFreshDatabaseWithoutRecovering(t *testing.T) {
	conn := openSchemaTestDB(t)
	migrationSource, err := newMigrationSource()
	if err != nil {
		t.Fatalf("open migration source: %v", err)
	}
	stale, err := staleMigrationState(conn, migrationSource)
	if err != nil {
		t.Fatalf("staleMigrationState: %v", err)
	}
	if stale != "" {
		t.Fatalf("fresh database reported stale: %s", stale)
	}

	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("initSchema: %v", err)
	}
	assertNewSchema(t, conn)
}

// A database already correct under the new numbering must be left alone. The
// row is the point: it proves the recovery is a recovery and not a wipe on
// every boot.
func TestInitSchemaLeavesCurrentDatabaseUntouched(t *testing.T) {
	conn := openSchemaTestDB(t)
	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("initial migrate: %v", err)
	}
	if _, err := conn.Exec(
		`INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES ('ada', 'x', 'y')`,
	); err != nil {
		t.Fatalf("seed user: %v", err)
	}

	migrationSource, err := newMigrationSource()
	if err != nil {
		t.Fatalf("open migration source: %v", err)
	}
	stale, err := staleMigrationState(conn, migrationSource)
	if err != nil {
		t.Fatalf("staleMigrationState: %v", err)
	}
	if stale != "" {
		t.Fatalf("current database reported stale: %s", stale)
	}

	if err := initSchema(&DatabaseSqlc{Db: conn}); err != nil {
		t.Fatalf("second initSchema: %v", err)
	}

	var username string
	if err := conn.QueryRow(`SELECT username FROM users`).Scan(&username); err != nil {
		t.Fatalf("the existing account was destroyed by a boot that should have been a no-op: %v", err)
	}
	if username != "ada" {
		t.Errorf("username = %q, want ada", username)
	}
	assertNewSchema(t, conn)
}
