package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"slices"
)

// ResetDatabase drops every object the application owns and re-runs the
// migrations from scratch, leaving a database at first-boot state on the same
// connection the caller already holds.
//
// It deliberately does not unlink quark.db. The process opens that file once at
// startup and keeps a *sql.DB and a *sql.Conn for its whole lifetime, and
// removing a file out from under a live handle disconnects nothing: the inode
// survives until the last descriptor closes, so queries keep succeeding against
// a file that no longer has a name and the reset only appears to have happened
// after a restart. Dropping and re-migrating in place keeps every handle valid,
// and re-runs the migrations from 000.
//
// The drop and the re-migration are one transaction that holds SQLite's write
// lock from its first statement (#3085). Another instance on the same database
// waits on that lock, or gives up busy, and then reads a complete first-boot
// schema: it never finds a table missing. The migrations issue a new install
// id (029_install), in that same transaction, which is what tells every
// instance to restart: see resetutil.Watch.
//
// golang-migrate's own Drop() cannot stand in for this: it issues DROP TABLE
// for every row in sqlite_master, sqlite_sequence included, and SQLite refuses
// to drop that one.
func ResetDatabase(database *DatabaseSqlc) error {
	if database == nil || database.Db == nil {
		return fmt.Errorf("database not initialized")
	}
	return exclusively(database.Db, func(ctx context.Context, conn *sql.Conn) error {
		kept, err := setAsideKeptTables(ctx, conn)
		if err != nil {
			return fmt.Errorf("failed to set aside the tables a reset keeps: %w", err)
		}
		if err := dropAllObjects(ctx, conn); err != nil {
			return fmt.Errorf("failed to drop database objects: %w", err)
		}
		if err := migrateFromScratch(ctx, conn); err != nil {
			return fmt.Errorf("failed to re-run migrations: %w", err)
		}
		if err := restoreKeptTables(ctx, conn, kept); err != nil {
			return fmt.Errorf("failed to restore the tables a reset keeps: %w", err)
		}
		return nil
	})
}

// keptTables are the tables whose rows outlive a reset: the Quark's settings
// and the account request history. Both were files in the data directory that
// a reset never touched (#3083), and the settings hold what a reset must not
// lose: the remote access household, the device id and the salt secret.
var keptTables = []string{"settings", "account_request_history"}

// setAsideKeptTables copies each of keptTables that exists into a temporary
// table, which dropAllObjects does not see, and returns the ones it copied. A
// database from before a table existed, or an empty one, has nothing to copy.
//
// These statements and restoreKeptTables' are DDL with the table name built
// in, from the fixed list above, which sqlc cannot express.
func setAsideKeptTables(ctx context.Context, conn *sql.Conn) ([]string, error) {
	kept := make([]string, 0, len(keptTables))
	for _, table := range keptTables {
		var exists bool
		if err := conn.QueryRowContext(ctx,
			`SELECT EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)`, table,
		).Scan(&exists); err != nil {
			return nil, err
		}
		if !exists {
			continue
		}
		if _, err := conn.ExecContext(ctx,
			fmt.Sprintf(`CREATE TEMP TABLE "kept_%s" AS SELECT * FROM "%s"`, table, table),
		); err != nil {
			return nil, err
		}
		kept = append(kept, table)
	}
	return kept, nil
}

// restoreKeptTables puts the rows setAsideKeptTables copied back into the
// tables the migrations just made, and drops the copies.
func restoreKeptTables(ctx context.Context, conn *sql.Conn, kept []string) error {
	for _, table := range kept {
		if _, err := conn.ExecContext(ctx, fmt.Sprintf(
			`INSERT INTO "%s" SELECT * FROM temp."kept_%s"; DROP TABLE temp."kept_%s"`, table, table, table,
		)); err != nil {
			return err
		}
	}
	return nil
}

// ResetRawDatabase empties a database that carries no migration set — the
// health database, whose tables are created by whatever writes to it rather
// than by migrations. There is nothing to re-run afterwards, so this drops the
// objects and stops.
//
// Like ResetDatabase it works through the caller's live handle instead of
// unlinking the file, for the same reason: the process holds the descriptor
// open for its lifetime.
func ResetRawDatabase(database *DatabaseRaw) error {
	if database == nil || database.Db == nil {
		return fmt.Errorf("database not initialized")
	}
	return exclusively(database.Db, func(ctx context.Context, conn *sql.Conn) error {
		if err := dropAllObjects(ctx, conn); err != nil {
			return fmt.Errorf("failed to drop health database objects: %w", err)
		}
		return nil
	})
}

// exclusively runs work in one transaction on one connection, holding the
// database's write lock from the start so that no other connection, in this
// process or another, sees work half done.
//
// BEGIN IMMEDIATE is issued by hand, which sqlc cannot express and
// database/sql's BeginTx does not offer: its BEGIN is deferred, and a deferred
// transaction that finds a writer ahead of it when it first writes fails busy
// at once instead of waiting its turn.
func exclusively(sqlDB *sql.DB, work func(ctx context.Context, conn *sql.Conn) error) (err error) {
	ctx := context.Background()
	conn, err := sqlDB.Conn(ctx)
	if err != nil {
		return fmt.Errorf("failed to take a database connection: %w", err)
	}
	defer func() { err = errors.Join(err, conn.Close()) }()

	if _, err := conn.ExecContext(ctx, `BEGIN IMMEDIATE`); err != nil {
		return fmt.Errorf("failed to lock the database: %w", err)
	}
	if err := work(ctx, conn); err != nil {
		_, rollbackErr := conn.ExecContext(ctx, `ROLLBACK`)
		return errors.Join(err, rollbackErr)
	}
	if _, err := conn.ExecContext(ctx, `COMMIT`); err != nil {
		_, rollbackErr := conn.ExecContext(ctx, `ROLLBACK`)
		return errors.Join(fmt.Errorf("failed to commit: %w", err), rollbackErr)
	}
	return nil
}

// migrateFromScratch applies every embedded migration to an empty database on
// conn, inside the caller's transaction, and records the version the way
// golang-migrate does, so the next boot's m.Up() finds nothing to do.
//
// golang-migrate cannot do this itself: it commits each migration on its own
// connection, which would release the lock ResetDatabase holds between the
// drop and the last migration. TestResetDatabase_LeavesTheSchemaMigrationsBuild
// holds this to what golang-migrate builds.
func migrateFromScratch(ctx context.Context, conn *sql.Conn) error {
	migrationSource, err := newMigrationSource()
	if err != nil {
		return err
	}
	// DDL, and the statements of golang-migrate's sqlite driver word for word.
	if _, err := conn.ExecContext(ctx, `
	CREATE TABLE IF NOT EXISTS schema_migrations (version uint64,dirty bool);
  CREATE UNIQUE INDEX IF NOT EXISTS version_unique ON schema_migrations (version);
  `); err != nil {
		return fmt.Errorf("failed to create schema_migrations: %w", err)
	}

	version, err := migrationSource.First()
	if err != nil {
		return fmt.Errorf("failed to find the first migration: %w", err)
	}
	for {
		body, _, err := migrationSource.ReadUp(version)
		if err != nil {
			return fmt.Errorf("failed to open migration %d: %w", version, err)
		}
		// A migration is a file embedded in this binary, so reading it whole
		// is bounded by us.
		statements, err := io.ReadAll(body)
		if err := errors.Join(err, body.Close()); err != nil {
			return fmt.Errorf("failed to read migration %d: %w", version, err)
		}
		if _, err := conn.ExecContext(ctx, string(statements)); err != nil {
			return fmt.Errorf("failed to apply migration %d: %w", version, err)
		}

		next, err := migrationSource.Next(version)
		if errors.Is(err, fs.ErrNotExist) {
			break
		}
		if err != nil {
			return fmt.Errorf("failed to find the migration after %d: %w", version, err)
		}
		version = next
	}

	if _, err := conn.ExecContext(ctx,
		`INSERT INTO schema_migrations (version, dirty) VALUES (?, ?)`, version, false,
	); err != nil {
		return fmt.Errorf("failed to record schema version %d: %w", version, err)
	}
	return nil
}

// dropAllObjects removes every table and view outside SQLite's own sqlite_%
// namespace. Triggers and indexes go with the tables that own them, and
// dropping an FTS5 virtual table takes its shadow tables with it — which is why
// each statement is IF EXISTS: the shadow rows are still in the snapshot of
// sqlite_master this read from.
//
// It needs no deferred-constraint dance under PRAGMA foreign_keys=on. Virtual
// tables go first, in the order sqlite_master lists them, because an FTS5
// table cannot be dropped once its shadow tables are gone. Everything else
// goes in reverse creation order, so every child is gone before its parents:
// creation order alone is not enough once a table has two parents
// (path_access references both users and groups), because dropping the second
// parent cascades into a child whose first parent no longer exists, and
// SQLite rejects that. Verified against a populated database by the
// delete-account tests, which reset one holding a user and a live session.
func dropAllObjects(ctx context.Context, conn *sql.Conn) error {
	const listObjects = `
		SELECT type, name, COALESCE(sql LIKE 'CREATE VIRTUAL TABLE%', 0) FROM sqlite_master
		WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'`

	rows, err := conn.QueryContext(ctx, listObjects)
	if err != nil {
		return fmt.Errorf("failed to list database objects: %w", err)
	}

	type object struct {
		kind, name string
		virtual    bool
	}
	objects := make([]object, 0)
	for rows.Next() {
		var o object
		if err := rows.Scan(&o.kind, &o.name, &o.virtual); err != nil {
			rows.Close()
			return fmt.Errorf("failed to read database object: %w", err)
		}
		objects = append(objects, o)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return fmt.Errorf("failed to list database objects: %w", err)
	}
	if err := rows.Close(); err != nil {
		return fmt.Errorf("failed to close object listing: %w", err)
	}

	ordered := make([]object, 0, len(objects))
	for _, o := range objects {
		if o.virtual {
			ordered = append(ordered, o)
		}
	}
	for _, o := range slices.Backward(objects) {
		if !o.virtual {
			ordered = append(ordered, o)
		}
	}

	for _, o := range ordered {
		// The kind is one of the two literals in listObjects and the name comes
		// from sqlite_master, so neither is caller-controlled; DDL takes no
		// bound parameters for identifiers in any case.
		statement := fmt.Sprintf(`DROP %s IF EXISTS "%s"`, o.kind, o.name)
		if _, err := conn.ExecContext(ctx, statement); err != nil {
			return fmt.Errorf("failed to drop %s %s: %w", o.kind, o.name, err)
		}
	}
	return nil
}
