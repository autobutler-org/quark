package db

import (
	"database/sql"
	"fmt"
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
// re-runs the migrations from 000, and needs no restart.
//
// golang-migrate's own Drop() cannot stand in for this: it issues DROP TABLE
// for every row in sqlite_master, sqlite_sequence included, and SQLite refuses
// to drop that one.
func ResetDatabase(database *DatabaseSqlc) error {
	if database == nil || database.Db == nil {
		return fmt.Errorf("database not initialized")
	}
	if err := dropAllObjects(database.Db); err != nil {
		return fmt.Errorf("failed to drop database objects: %w", err)
	}
	if err := initSchema(database); err != nil {
		return fmt.Errorf("failed to re-run migrations: %w", err)
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
	if err := dropAllObjects(database.Db); err != nil {
		return fmt.Errorf("failed to drop health database objects: %w", err)
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
func dropAllObjects(sqlDB *sql.DB) error {
	const listObjects = `
		SELECT type, name, COALESCE(sql LIKE 'CREATE VIRTUAL TABLE%', 0) FROM sqlite_master
		WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'`

	rows, err := sqlDB.Query(listObjects)
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
		if _, err := sqlDB.Exec(statement); err != nil {
			return fmt.Errorf("failed to drop %s %s: %w", o.kind, o.name, err)
		}
	}
	return nil
}
