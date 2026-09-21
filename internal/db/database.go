// Package db is Quark's SQLite layer: the connection, the golang-migrate migrations under migrations/, and the
// query methods sqlc generates from sql/queries/. Code outside this package reaches the database through those
// generated methods.
package db

import (
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"

	// Registers the "sqlite" database/sql driver used by every connection here.
	_ "modernc.org/sqlite"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/sqlite"
	"github.com/golang-migrate/migrate/v4/source"
	"github.com/golang-migrate/migrate/v4/source/iofs"
)

type DatabaseSqlc struct {
	Db      *sql.DB
	Queries *Queries
}

type DatabaseRaw struct {
	Db *sql.DB
}

func (d *DatabaseSqlc) Exec(query string, args ...any) (sql.Result, error) {
	if d == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	return d.Db.Exec(query, args...)
}

func (d *DatabaseSqlc) Query(query string, args ...any) (*sql.Rows, error) {
	if d == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	return d.Db.Query(query, args...)
}

func (d *DatabaseRaw) Exec(query string, args ...any) (sql.Result, error) {
	if d == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	return d.Db.Exec(query, args...)
}

func (d *DatabaseRaw) Query(query string, args ...any) (*sql.Rows, error) {
	if d == nil {
		return nil, fmt.Errorf("database not initialized")
	}
	return d.Db.Query(query, args...)
}

//go:embed migrations
var migrations embed.FS

// newMigrationSource opens the embedded migration set.
func newMigrationSource() (source.Driver, error) {
	migrationSource, err := iofs.New(migrations, "migrations")
	if err != nil {
		return nil, fmt.Errorf("failed to create iofs source: %w", err)
	}
	return migrationSource, nil
}

func initSchema(database *DatabaseSqlc) error {
	migrationSource, err := newMigrationSource()
	if err != nil {
		return err
	}

	// Checked before the migrate instance is built, because building one
	// creates schema_migrations and an empty table is indistinguishable from a
	// database that never had one.
	stale, err := staleMigrationState(database.Db, migrationSource)
	if err != nil {
		return err
	}
	if stale != "" {
		slog.Warn(
			"discarding this machine's database and rebuilding it from scratch: "+
				"the schema version recorded on disk cannot be carried forward by this "+
				"build's migrations. Everything stored locally - the account, its "+
				"sessions, connected devices, photo albums and vault entries - is "+
				"deleted, and the appliance comes back at first-boot setup. Quark is "+
				"pre-release, so recovering automatically is preferred to refusing to "+
				"start.",
			"reason", stale,
		)
		return ResetDatabase(database)
	}

	driver, err := sqlite.WithInstance(database.Db, &sqlite.Config{})
	if err != nil {
		return fmt.Errorf("failed to create sqlite driver: %w", err)
	}
	m, err := migrate.NewWithInstance("iofs", migrationSource, "sqlite", driver)
	if err != nil {
		return fmt.Errorf("failed to create migrate instance: %w", err)
	}
	// ErrNoChange just means the schema is already at the latest migration.
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("failed to run migrations: %w", err)
	}
	return nil
}

// authMigrationVersion is 001_auth, the migration that creates users.is_admin.
// staleMigrationState leans on it: any version at or above this one implies the
// column exists, so its absence proves the number came from a different
// numbering. Regrouping the migration set again means revisiting this.
const authMigrationVersion = 1

// staleMigrationState says, in words, why the migration state recorded in sqlDB
// cannot be carried forward by the embedded migration set, or returns "" when
// it can and the migrations should simply run up.
//
// Three things make a recorded state unusable, and only the first announces
// itself:
//
//   - The version is absent from the embedded set. golang-migrate refuses
//     outright - "no migration found for version 21: read down for version 21
//     migrations: file does not exist" - and because that error travels out
//     through ConnectToDatabase the server does not start at all. Regrouping
//     the set by subject area (#1758) turned this from a hypothetical into the
//     state of every machine that ran Quark before it: those databases are
//     stamped as high as 21 and the set now tops out at 007.
//
//   - The version is present but was stamped under the old numbering, which
//     overlaps the new one across 0-7. This one is silent, and worse for it.
//     Old 3 meant connected_devices, auth and device names; new 003 means auth,
//     storage devices and connected devices. golang-migrate compares numbers
//     and inspects nothing, so it would cheerfully apply 004 onward onto a
//     schema with no device_roles table, no users.is_admin and no
//     sessions.last_used_at, then report success.
//
//   - The dirty flag is set. A half-applied migration leaves a schema matching
//     neither the version below it nor the one above, and nothing on disk says
//     which statements ran.
//
// users.is_admin is what separates the second case from a legitimately older
// database. Every version in the new set is at or above 001_auth, which creates
// users with that column, so under the new numbering "version >= 1" implies the
// column exists. Under the old numbering it did not arrive until 016. A
// database claiming a version this set can serve, without that column, is
// therefore stamped in the old numbering whatever its number says - which is
// the one check that catches the 0-7 overlap, since old 002 already created a
// users table and merely looking for that table would wave old 3 straight
// through.
//
// Deliberately narrow: a database correctly stamped under the new numbering,
// and a fresh one with nothing recorded at all, both return "" and migrate up
// untouched.
func staleMigrationState(sqlDB *sql.DB, migrationSource source.Driver) (string, error) {
	var tableExists int
	if err := sqlDB.QueryRow(
		`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations'`,
	).Scan(&tableExists); err != nil {
		return "", fmt.Errorf("failed to look for schema_migrations: %w", err)
	}
	if tableExists == 0 {
		return "", nil
	}

	var version uint
	var dirty bool
	err := sqlDB.QueryRow(`SELECT version, dirty FROM schema_migrations LIMIT 1`).Scan(&version, &dirty)
	if errors.Is(err, sql.ErrNoRows) {
		// The table is created before the first migration runs, so an empty one
		// is a fresh database rather than a stale one.
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("failed to read the recorded schema version: %w", err)
	}

	if dirty {
		return fmt.Sprintf("migration %d was left half-applied and the database is marked dirty", version), nil
	}

	body, _, err := migrationSource.ReadUp(version)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return fmt.Sprintf("version %d is not in this build's migration set", version), nil
		}
		return "", fmt.Errorf("failed to look up migration %d: %w", version, err)
	}
	if err := body.Close(); err != nil {
		return "", fmt.Errorf("failed to close migration %d: %w", version, err)
	}

	// Guarded rather than unconditional so that regrouping the set again - the
	// thing that caused this whole problem - cannot turn the check into a wipe
	// of every database below the auth migration.
	if version < authMigrationVersion {
		return "", nil
	}

	var hasAdminColumn int
	if err := sqlDB.QueryRow(
		`SELECT COUNT(*) FROM pragma_table_info('users') WHERE name = 'is_admin'`,
	).Scan(&hasAdminColumn); err != nil {
		return "", fmt.Errorf("failed to inspect the users table: %w", err)
	}
	if hasAdminColumn == 0 {
		return fmt.Sprintf(
			"version %d is stamped under the old numbering: users.is_admin is missing, "+
				"and 001_auth creates it", version), nil
	}

	return "", nil
}
