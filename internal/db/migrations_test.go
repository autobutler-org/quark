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

	// Stop at 008: 014 gives albums an owner and deletes them when there is none.
	if err := m.Migrate(uniqueAlbumNamesVersion); err != nil {
		t.Fatalf("migrate to %d: %v", uniqueAlbumNamesVersion, err)
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
		"calendars", "calendar_events",
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
		"users":           {"is_admin", "status"},
		"sessions":        {"last_used_at"},
		"photo_hashes":    {"dhash", "content_hash"},
		"photo_albums":    {"user_id"},
		"photo_favorites": {"user_id"},
		"calendar_events": {"created_by"},
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

	// So is the one calendar every account shares (#1144).
	var calendars int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM calendars WHERE is_default = 1 AND name = 'Personal'`).Scan(&calendars); err != nil {
		t.Fatalf("count calendars: %v", err)
	}
	if calendars != 1 {
		t.Errorf("default calendar rows = %d, want 1", calendars)
	}
}

// userStatusVersion is 011_user_status, the migration that adds users.status.
const userStatusVersion = 11

// TestUserStatusMigration checks an account that existed before 011 comes out
// active, the column refuses a status it does not know, and the migration
// rolls back cleanly.
func TestUserStatusMigration(t *testing.T) {
	conn, err := sql.Open("sqlite", DSN(filepath.Join(t.TempDir(), "quark.db")))
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
	if err := m.Migrate(userStatusVersion - 1); err != nil {
		t.Fatalf("migrate to %d: %v", userStatusVersion-1, err)
	}
	if _, err := conn.Exec(`INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES ('founder', 'h', 'r')`); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := m.Migrate(userStatusVersion); err != nil {
		t.Fatalf("migrate to %d: %v", userStatusVersion, err)
	}
	var status string
	if err := conn.QueryRow(`SELECT status FROM users WHERE username = 'founder'`).Scan(&status); err != nil {
		t.Fatalf("read status: %v", err)
	}
	if status != "active" {
		t.Errorf("existing account status = %q, want active", status)
	}
	if _, err := conn.Exec(`UPDATE users SET status = 'banned' WHERE username = 'founder'`); err == nil {
		t.Error("status accepted a value outside pending, active and disabled")
	}

	if err := m.Migrate(userStatusVersion - 1); err != nil {
		t.Fatalf("roll back to %d: %v", userStatusVersion-1, err)
	}
	var columns int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('users') WHERE name = 'status'`).Scan(&columns); err != nil {
		t.Fatalf("inspect users: %v", err)
	}
	if columns != 0 {
		t.Error("users.status survived the down migration")
	}
}

// groupNameNocaseVersion is 012_group_name_nocase, the migration that makes
// group names unique ignoring case (#1910).
const groupNameNocaseVersion = 12

// TestGroupNameNocaseMigration checks two groups can't differ only by case
// once 012 runs, that the everyone group and its grants survive it, and that
// the migration rolls back cleanly.
func TestGroupNameNocaseMigration(t *testing.T) {
	conn, err := sql.Open("sqlite", DSN(filepath.Join(t.TempDir(), "quark.db")))
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
	if err := m.Migrate(groupNameNocaseVersion - 1); err != nil {
		t.Fatalf("migrate to %d: %v", groupNameNocaseVersion-1, err)
	}
	if _, err := conn.Exec(`INSERT INTO path_access (rel_path, group_id, level) SELECT 'shared', id, 'read' FROM groups WHERE name = 'everyone'`); err != nil {
		t.Fatalf("seed grant: %v", err)
	}

	if err := m.Migrate(groupNameNocaseVersion); err != nil {
		t.Fatalf("migrate to %d: %v", groupNameNocaseVersion, err)
	}
	var grants int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&grants); err != nil {
		t.Fatalf("count grants: %v", err)
	}
	if grants != 1 {
		t.Errorf("grants after migration = %d, want the everyone grant kept", grants)
	}
	if _, err := conn.Exec(`INSERT INTO groups (name) VALUES ('Family')`); err != nil {
		t.Fatalf("insert Family: %v", err)
	}
	if _, err := conn.Exec(`INSERT INTO groups (name) VALUES ('family')`); err == nil {
		t.Error("inserted family next to Family")
	}
	if _, err := conn.Exec(`INSERT INTO groups (name) VALUES ('EVERYONE')`); err == nil {
		t.Error("inserted EVERYONE next to everyone")
	}

	if err := m.Migrate(groupNameNocaseVersion - 1); err != nil {
		t.Fatalf("roll back to %d: %v", groupNameNocaseVersion-1, err)
	}
	if _, err := conn.Exec(`INSERT INTO groups (name) VALUES ('family')`); err != nil {
		t.Errorf("family still refused after the down migration: %v", err)
	}
}

// migrateTo opens a database and applies migrations up to version.
func migrateTo(t *testing.T, version uint) (*sql.DB, *migrate.Migrate) {
	t.Helper()
	conn, err := sql.Open("sqlite", DSN(filepath.Join(t.TempDir(), "quark.db")))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
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
	if err := m.Migrate(version); err != nil {
		t.Fatalf("migrate to %d: %v", version, err)
	}
	return conn, m
}

// count runs a COUNT query.
func count(t *testing.T, conn *sql.DB, query string, args ...any) int {
	t.Helper()
	var n int
	if err := conn.QueryRow(query, args...).Scan(&n); err != nil {
		t.Fatalf("%s: %v", query, err)
	}
	return n
}

// jobOwnerVersion is 013_job_owner, the migration that records who queued a
// job (#1979).
const jobOwnerVersion = 13

// TestJobOwnerMigration leaves existing jobs with no owner, deletes an
// account's jobs with it, and rolls back and forward again keeping every row.
func TestJobOwnerMigration(t *testing.T) {
	conn, m := migrateTo(t, jobOwnerVersion-1)
	if _, err := conn.Exec(`
INSERT INTO users (id, username, password_hash, recovery_phrase_hash) VALUES (1, 'bob', 'h', 'r'), (2, 'carol', 'h', 'r');
INSERT INTO jobs (id, kind, name, status, params, lane, error) VALUES
	(1, 'video-transcode', 'old', 'failed', '{"relPath":"a.mkv"}', 'encode', 'boom'),
	(2, 'video-transcode', 'older', 'completed', '{}', 'copy', '');
`); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := m.Migrate(jobOwnerVersion); err != nil {
		t.Fatalf("migrate to %d: %v", jobOwnerVersion, err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM jobs WHERE user_id IS NULL`); n != 2 {
		t.Errorf("existing jobs with no owner = %d, want 2", n)
	}
	if _, err := conn.Exec(`INSERT INTO jobs (kind, name, user_id) VALUES ('video-transcode', 'nobody', 99)`); err == nil {
		t.Error("a job owned by a missing account was accepted")
	}
	if _, err := conn.Exec(`
INSERT INTO jobs (id, kind, name, user_id) VALUES (3, 'video-transcode', 'bob''s', 1), (4, 'video-transcode', 'carol''s', 2);
DELETE FROM users WHERE id = 1;`); err != nil {
		t.Fatalf("delete account: %v", err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM jobs WHERE id = 3`); n != 0 {
		t.Error("a deleted account's job was kept")
	}

	// Down, up, and down and up once more.
	for range 2 {
		if err := m.Migrate(jobOwnerVersion - 1); err != nil {
			t.Fatalf("roll back to %d: %v", jobOwnerVersion-1, err)
		}
		if n := count(t, conn, `SELECT COUNT(*) FROM jobs WHERE id IN (1, 2, 4)`); n != 3 {
			t.Errorf("jobs after the down migration = %d, want 3", n)
		}
		if n := count(t, conn, `SELECT COUNT(*) FROM jobs WHERE id = 1 AND status = 'failed' AND error = 'boom' AND lane = 'encode'`); n != 1 {
			t.Error("the down migration changed a job's columns")
		}
		if n := count(t, conn, `SELECT COUNT(*) FROM pragma_table_info('jobs') WHERE name = 'user_id'`); n != 0 {
			t.Error("jobs.user_id is still there after the down migration")
		}
		if n := count(t, conn, `SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_jobs_status_id'`); n != 1 {
			t.Error("idx_jobs_status_id is missing after the down migration")
		}
		if err := m.Migrate(jobOwnerVersion); err != nil {
			t.Fatalf("migrate to %d again: %v", jobOwnerVersion, err)
		}
		if n := count(t, conn, `SELECT COUNT(*) FROM jobs WHERE user_id IS NULL`); n != 3 {
			t.Errorf("jobs after migrating up again = %d, want 3 with no owner", n)
		}
	}
	if _, err := conn.Exec(`INSERT INTO jobs (kind, name) VALUES ('video-transcode', 'new')`); err != nil {
		t.Fatalf("insert after the round trip: %v", err)
	}
	if n := count(t, conn, `SELECT MAX(id) FROM jobs`); n != 5 {
		t.Errorf("new job id = %d, want 5: the rebuild must not reuse ids", n)
	}
}

// perUserPhotosVersion is 014_per_user_photos, the migration that gives
// favorites and albums an owner (#1912).
const perUserPhotosVersion = 14

// TestPerUserPhotosMigration gives existing favorites and albums to the oldest
// admin, lets two accounts then hold the same album name, and rolls back to
// the oldest admin's rows.
func TestPerUserPhotosMigration(t *testing.T) {
	conn, m := migrateTo(t, perUserPhotosVersion-1)
	if _, err := conn.Exec(`
INSERT INTO users (id, username, password_hash, recovery_phrase_hash, created_at, is_admin) VALUES
	(1, 'member',  'h', 'r', '2024-01-01 00:00:00', 0), -- oldest, but not an admin
	(2, 'late',    'h', 'r', '2024-03-01 00:00:00', 1),
	(3, 'founder', 'h', 'r', '2024-02-01 00:00:00', 1), -- oldest admin
	(4, 'tie',     'h', 'r', '2024-02-01 00:00:00', 1); -- same time, higher id
INSERT INTO photo_albums (id, name, parent_id, smart_type) VALUES
	(1, 'Favorites', NULL, 'favorites'),
	(2, 'Trips',     NULL, NULL),
	(3, 'Japan',     2,    NULL);
INSERT INTO photo_album_items (album_id, device_serial, rel_path) VALUES (1, '', 'a.jpg'), (3, '', 'b.jpg');
INSERT INTO photo_favorites (device_serial, rel_path) VALUES ('', 'a.jpg'), ('USB', 'c.jpg');
`); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := m.Migrate(perUserPhotosVersion); err != nil {
		t.Fatalf("migrate to %d: %v", perUserPhotosVersion, err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM photo_albums WHERE user_id = 3`); n != 3 {
		t.Errorf("albums owned by the oldest admin = %d, want 3", n)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM photo_album_items`); n != 2 {
		t.Errorf("album items after migration = %d, want both kept", n)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM photo_favorites WHERE user_id = 3`); n != 2 {
		t.Errorf("favorites owned by the oldest admin = %d, want 2", n)
	}

	// Another account can hold its own Favorites album, root Trips and the
	// same favorite; the same account still cannot hold two.
	for _, stmt := range []string{
		`INSERT INTO photo_albums (id, name, smart_type, user_id) VALUES (4, 'Favorites', 'favorites', 1)`,
		`INSERT INTO photo_albums (id, name, user_id) VALUES (5, 'trips', 1)`,
		`INSERT INTO photo_favorites (user_id, device_serial, rel_path) VALUES (1, '', 'a.jpg')`,
	} {
		if _, err := conn.Exec(stmt); err != nil {
			t.Errorf("%s: %v", stmt, err)
		}
	}
	for _, stmt := range []string{
		`INSERT INTO photo_albums (name, smart_type, user_id) VALUES ('Favorites 2', 'favorites', 3)`,
		`INSERT INTO photo_albums (name, user_id) VALUES ('TRIPS', 3)`,
		`INSERT INTO photo_favorites (user_id, device_serial, rel_path) VALUES (3, '', 'a.jpg')`,
		`INSERT INTO photo_favorites (user_id, rel_path) VALUES (99, 'x.jpg')`,
	} {
		if _, err := conn.Exec(stmt); err == nil {
			t.Errorf("%s: accepted, want a constraint failure", stmt)
		}
	}

	// Deleting an account deletes its favorites and albums.
	if _, err := conn.Exec(`INSERT INTO users (id, username, password_hash, recovery_phrase_hash) VALUES (5, 'gone', 'h', 'r');
INSERT INTO photo_albums (name, user_id) VALUES ('Gone', 5);
INSERT INTO photo_favorites (user_id, rel_path) VALUES (5, 'g.jpg');
DELETE FROM users WHERE id = 5;`); err != nil {
		t.Fatalf("delete account: %v", err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM photo_albums WHERE name = 'Gone'`) +
		count(t, conn, `SELECT COUNT(*) FROM photo_favorites WHERE rel_path = 'g.jpg'`); n != 0 {
		t.Errorf("rows left after deleting their account = %d, want 0", n)
	}

	if err := m.Migrate(perUserPhotosVersion - 1); err != nil {
		t.Fatalf("roll back to %d: %v", perUserPhotosVersion-1, err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM photo_albums`); n != 3 {
		t.Errorf("albums after the down migration = %d, want the oldest admin's 3", n)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM photo_favorites`); n != 2 {
		t.Errorf("favorites after the down migration = %d, want 2 with the duplicate folded", n)
	}
	if _, err := conn.Exec(`INSERT INTO photo_albums (name) VALUES ('TRIPS')`); err == nil {
		t.Error("a second root TRIPS was accepted after the down migration")
	}
}

// TestPerUserPhotosMigrationWithoutAdmin deletes favorites and albums nobody
// can own instead of failing.
func TestPerUserPhotosMigrationWithoutAdmin(t *testing.T) {
	conn, m := migrateTo(t, perUserPhotosVersion-1)
	if _, err := conn.Exec(`
INSERT INTO photo_albums (id, name, parent_id) VALUES (1, 'Trips', NULL), (2, 'Japan', 1);
INSERT INTO photo_album_items (album_id, device_serial, rel_path) VALUES (2, '', 'b.jpg');
INSERT INTO photo_favorites (rel_path) VALUES ('a.jpg');
`); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := m.Migrate(perUserPhotosVersion); err != nil {
		t.Fatalf("migrate to %d: %v", perUserPhotosVersion, err)
	}
	for _, table := range []string{"photo_albums", "photo_album_items", "photo_favorites"} {
		if n := count(t, conn, `SELECT COUNT(*) FROM `+table); n != 0 {
			t.Errorf("%s rows with no admin = %d, want 0", table, n)
		}
	}
	if err := m.Migrate(perUserPhotosVersion - 1); err != nil {
		t.Fatalf("roll back to %d: %v", perUserPhotosVersion-1, err)
	}
}

// calendarEventOwnerVersion is 022_calendar_event_owner, which records who
// created each calendar event (#2544).
const calendarEventOwnerVersion = 22

// TestCalendarEventOwnerMigration checks events from before 022 keep no owner,
// a deleted account's events stay with their owner cleared, and the rebuild
// on the way down keeps every event.
func TestCalendarEventOwnerMigration(t *testing.T) {
	conn, m := migrateTo(t, calendarEventOwnerVersion-1)
	if _, err := conn.Exec(`
INSERT INTO users (id, username, password_hash, recovery_phrase_hash) VALUES (1, 'maya', 'h', 'r');
INSERT INTO calendar_events (id, calendar_id, title, starts_at, ends_at) VALUES
	(1, 1, 'Old', '2026-09-01T09:00:00Z', '2026-09-01T10:00:00Z');
`); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := m.Migrate(calendarEventOwnerVersion); err != nil {
		t.Fatalf("migrate to %d: %v", calendarEventOwnerVersion, err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM calendar_events WHERE created_by IS NULL`); n != 1 {
		t.Errorf("events with no owner after migration = %d, want the old one", n)
	}
	if _, err := conn.Exec(`INSERT INTO calendar_events (id, calendar_id, title, starts_at, ends_at, created_by) VALUES
	(2, 1, 'Mine', '2026-09-02T09:00:00Z', '2026-09-02T10:00:00Z', 1)`); err != nil {
		t.Fatalf("insert an owned event: %v", err)
	}
	if _, err := conn.Exec(`DELETE FROM users WHERE id = 1`); err != nil {
		t.Fatalf("delete the owner: %v", err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM calendar_events WHERE created_by IS NULL`); n != 2 {
		t.Errorf("events with no owner after deleting it = %d, want both kept", n)
	}

	if err := m.Migrate(calendarEventOwnerVersion - 1); err != nil {
		t.Fatalf("migrate down: %v", err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM calendar_events`); n != 2 {
		t.Errorf("events after the down migration = %d, want 2", n)
	}
}

// calendarEventChecksVersion is 023_calendar_event_checks, which bounds an
// event's color and reminder in the schema as well as the app (#2536).
const calendarEventChecksVersion = 23

// TestCalendarEventChecksMigration clamps the colors and reminders already
// stored out of range, refuses new ones, and rolls back keeping every event,
// its owner and both indexes.
func TestCalendarEventChecksMigration(t *testing.T) {
	conn, m := migrateTo(t, calendarEventChecksVersion-1)
	if _, err := conn.Exec(`
INSERT INTO users (id, username, password_hash, recovery_phrase_hash) VALUES (1, 'maya', 'h', 'r');
INSERT INTO calendar_events (id, calendar_id, title, starts_at, ends_at, all_day, reminder_minutes, color_index, created_by) VALUES
	(1, 1, 'Fine',          '2026-09-01T09:00:00Z', '2026-09-01T10:00:00Z', 0, 30,     2,   1),
	(2, 1, 'Low color',     '2026-09-01T09:00:00Z', '2026-09-01T10:00:00Z', 0, NULL,   -1,  NULL),
	(3, 1, 'High color',    '2026-09-01T09:00:00Z', '2026-09-01T10:00:00Z', 0, NULL,   99,  NULL),
	(4, 1, 'Late timed',    '2026-09-01T09:00:00Z', '2026-09-01T10:00:00Z', 0, -1,     0,   NULL),
	(5, 1, 'Early',         '2026-09-01T09:00:00Z', '2026-09-01T10:00:00Z', 0, 999999, 0,   NULL),
	(6, 1, 'Late all day',  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z', 1, -1440,  0,   NULL),
	(7, 1, '9 AM on day',   '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z', 1, -540,   5,   NULL),
	(8, 1, 'Fractional',    '2026-09-01T09:00:00Z', '2026-09-01T10:00:00Z', 0, 30.7,   2.5, NULL);
`); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if err := m.Migrate(calendarEventChecksVersion); err != nil {
		t.Fatalf("migrate to %d: %v", calendarEventChecksVersion, err)
	}
	want := map[int64][2]any{
		1: {int64(2), int64(30)},
		2: {int64(0), nil},
		3: {int64(5), nil},
		4: {int64(0), int64(0)},
		5: {int64(0), int64(7 * 24 * 60)},
		6: {int64(0), int64(-1439)},
		7: {int64(5), int64(-540)},
		8: {int64(2), int64(30)},
	}
	for id, w := range want {
		var color, reminder any
		if err := conn.QueryRow(`SELECT color_index, reminder_minutes FROM calendar_events WHERE id = ?`, id).Scan(&color, &reminder); err != nil {
			t.Fatalf("read event %d: %v", id, err)
		}
		if color != w[0] || reminder != w[1] {
			t.Errorf("event %d color, reminder = %v (%T), %v (%T), want %v, %v", id, color, color, reminder, reminder, w[0], w[1])
		}
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM calendar_events WHERE id = 1 AND created_by = 1 AND title = 'Fine'`); n != 1 {
		t.Error("the rebuild lost an event's owner or title")
	}

	insert := `INSERT INTO calendar_events (calendar_id, title, starts_at, ends_at, all_day, reminder_minutes, color_index) VALUES (1, 'x', 'a', 'b', ?, ?, ?)`
	for _, ok := range [][3]any{
		{0, nil, 0}, {0, 0, 5}, {0, 7 * 24 * 60, 3}, {1, -1439, 1}, {1, 7 * 24 * 60, 0},
	} {
		if _, err := conn.Exec(insert, ok[0], ok[1], ok[2]); err != nil {
			t.Errorf("all day %v, reminder %v, color %v refused: %v", ok[0], ok[1], ok[2], err)
		}
	}
	for _, bad := range [][3]any{
		{0, nil, -1}, {0, nil, 6}, {0, nil, 2.5}, {0, nil, "red"},
		{0, -1, 0}, {0, 7*24*60 + 1, 0}, {1, -1440, 0}, {0, 30.5, 0}, {0, "soon", 0},
	} {
		if _, err := conn.Exec(insert, bad[0], bad[1], bad[2]); err == nil || !strings.Contains(err.Error(), "CHECK constraint failed") {
			t.Errorf("all day %v, reminder %v, color %v = %v, want a check failure", bad[0], bad[1], bad[2], err)
		}
	}
	if _, err := conn.Exec(`UPDATE calendar_events SET all_day = 0 WHERE id = 7`); err == nil {
		t.Error("an all-day reminder after midnight survived the event becoming timed")
	}

	if err := m.Migrate(calendarEventChecksVersion - 1); err != nil {
		t.Fatalf("migrate down: %v", err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM calendar_events`); n != 13 {
		t.Errorf("events after the down migration = %d, want 13", n)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM calendar_events WHERE id = 1 AND created_by = 1`); n != 1 {
		t.Error("the down migration lost an event's owner")
	}
	for _, index := range []string{"idx_calendar_events_start", "idx_calendar_events_created_by"} {
		if n := count(t, conn, `SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?`, index); n != 1 {
			t.Errorf("%s missing after the down migration", index)
		}
	}
	if _, err := conn.Exec(insert, 0, nil, 99); err != nil {
		t.Errorf("color 99 still refused after the down migration: %v", err)
	}
	// Up again clamps what the down migration let in.
	if err := m.Migrate(calendarEventChecksVersion); err != nil {
		t.Fatalf("migrate up again: %v", err)
	}
	if n := count(t, conn, `SELECT COUNT(*) FROM calendar_events WHERE color_index NOT BETWEEN 0 AND 5`); n != 0 {
		t.Errorf("colors out of range after migrating up again = %d", n)
	}
	for _, index := range []string{"idx_calendar_events_start", "idx_calendar_events_created_by"} {
		if n := count(t, conn, `SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = ?`, index); n != 1 {
			t.Errorf("%s missing after the up migration", index)
		}
	}
}
