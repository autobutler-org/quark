package db

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/sqlite"
	_ "modernc.org/sqlite"
)

// uniqueAlbumNamesVersion is 008_unique_album_names, the migration that repairs
// existing album names and adds idx_photo_albums_sibling_name.
const uniqueAlbumNamesVersion = 8

// TestUniqueAlbumNamesMigration seeds the album shapes a real device can hold
// before 008 and checks the migration repairs every one of them instead of
// failing on the index, which would leave the database dirty.
func TestUniqueAlbumNamesMigration(t *testing.T) {
	path := filepath.Join(t.TempDir(), "quark.db")
	conn, err := sql.Open("sqlite", DSN(path))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer conn.Close()

	migrationSource, err := newMigrationSource()
	if err != nil {
		t.Fatalf("source: %v", err)
	}
	driver, err := sqlite.WithInstance(conn, &sqlite.Config{})
	if err != nil {
		t.Fatalf("driver: %v", err)
	}
	m, err := migrate.NewWithInstance("iofs", migrationSource, "sqlite", driver)
	if err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if err := m.Migrate(uniqueAlbumNamesVersion - 1); err != nil {
		t.Fatalf("migrate to %d: %v", uniqueAlbumNamesVersion-1, err)
	}

	if _, err := conn.Exec(`
INSERT INTO photo_albums (id, name, parent_id, smart_type) VALUES
	(1,  'Trips',       NULL, NULL),        -- oldest root Trips keeps its name
	(2,  'Trips',       NULL, NULL),        -- second root Trips
	(3,  'Parent',      NULL, NULL),
	(4,  'trips',       3,    NULL),        -- oldest in its group; other parent than 1
	(5,  'Trips',       3,    NULL),        -- case-only clash with 4
	(6,  'Japan',       1,    NULL),        -- same name, different parents: untouched
	(7,  'Japan',       3,    NULL),
	(8,  'Cats/Dogs',   3,    NULL),        -- slash replaced, no clash
	(9,  'Summer-2024', NULL, NULL),
	(10, 'Summer/2024', NULL, NULL),        -- slash replacement clashes with 9
	(11, 'favorites',   NULL, NULL),        -- user album holding the system name
	(12, 'Beach',       NULL, NULL),
	(13, 'Beach',       NULL, NULL),
	(14, 'Beach (13)',  NULL, NULL),        -- already holds 13's first candidate
	(15, 'Favorites',   3,    NULL),        -- nested Favorites is not reserved
	(16, 'Favorites',   NULL, 'favorites'); -- the system album keeps its name
`); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := m.Up(); err != nil {
		t.Fatalf("migrate up: %v", err)
	}

	want := map[int64]string{
		1:  "Trips",
		2:  "Trips (2)",
		3:  "Parent",
		4:  "trips",
		5:  "Trips (5)",
		6:  "Japan",
		7:  "Japan",
		8:  "Cats-Dogs",
		9:  "Summer-2024",
		10: "Summer-2024 (10)",
		11: "favorites (11)",
		12: "Beach",
		13: "Beach (13.1)",
		14: "Beach (13)",
		15: "Favorites",
		16: "Favorites",
	}
	rows, err := conn.Query(`SELECT id, name FROM photo_albums`)
	if err != nil {
		t.Fatalf("list albums: %v", err)
	}
	defer rows.Close()
	got := map[int64]string{}
	for rows.Next() {
		var id int64
		var name string
		if err := rows.Scan(&id, &name); err != nil {
			t.Fatalf("scan: %v", err)
		}
		got[id] = name
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("rows: %v", err)
	}
	for id, name := range want {
		if got[id] != name {
			t.Errorf("album %d = %q, want %q", id, got[id], name)
		}
	}

	// The index now refuses a root clash that differs only in case.
	_, err = conn.Exec(`INSERT INTO photo_albums (name) VALUES ('TRIPS')`)
	if err == nil || !strings.Contains(err.Error(), "UNIQUE constraint failed") {
		t.Errorf("inserting a root TRIPS = %v, want a unique constraint failure", err)
	}
}

// The embedded migration set must apply cleanly to an empty database and leave
// the schema the rest of the codebase queries. It deliberately asserts on
// tables and columns rather than on a version number: the set is regrouped by
// subject area rather than appended to, so the version is an implementation
// detail and pinning it only breaks the next regrouping (#1758).
func TestMigrationsApplyCleanly(t *testing.T) {
	path := filepath.Join(t.TempDir(), "quark.db")
	conn, err := sql.Open("sqlite", DSN(path))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer conn.Close()

	database := &DatabaseSqlc{Db: conn}
	if err := initSchema(database); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	var version int
	var dirty bool
	if err := conn.QueryRow(`SELECT version, dirty FROM schema_migrations`).Scan(&version, &dirty); err != nil {
		t.Fatalf("read schema_migrations: %v", err)
	}
	if dirty {
		t.Fatal("migrations left the database dirty")
	}

	tables := []string{
		"users", "sessions",
		"device_names", "device_roles",
		"connected_devices",
		"photo_albums", "photo_album_items", "photo_rotations", "photo_favorites", "photo_hashes",
		"vault_config", "vault_folders", "vault_entries", "vault_location",
		"file_content", "file_content_fts",
		"vfs_metadata", "vfs_db_entries",
		"groups", "group_members", "path_access",
	}
	for _, table := range tables {
		var count int
		if err := conn.QueryRow(
			`SELECT COUNT(*) FROM sqlite_master WHERE name = ?`, table,
		).Scan(&count); err != nil {
			t.Fatalf("look up %s: %v", table, err)
		}
		if count != 1 {
			t.Errorf("table %s missing after migration", table)
		}
	}

	columns := map[string][]string{
		"users":        {"is_admin"},
		"sessions":     {"last_used_at"},
		"photo_hashes": {"dhash", "content_hash"},
	}
	for table, names := range columns {
		for _, name := range names {
			var count int
			if err := conn.QueryRow(
				`SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?`, table, name,
			).Scan(&count); err != nil {
				t.Fatalf("inspect %s: %v", table, err)
			}
			if count != 1 {
				t.Errorf("%s.%s missing after migration", table, name)
			}
		}
	}

	// The vault location singleton is seeded by the migration, not by the app.
	var located int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM vault_location WHERE id = 1`).Scan(&located); err != nil {
		t.Fatalf("count vault_location: %v", err)
	}
	if located != 1 {
		t.Errorf("vault_location seed row missing, got %d rows", located)
	}
}
