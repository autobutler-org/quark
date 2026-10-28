package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"slices"

	"github.com/golang-migrate/migrate/v4/source"
	"github.com/golang-migrate/migrate/v4/source/iofs"
)

// resetPostgres is ResetDatabase on PostgreSQL: every object the migrations
// made is dropped and made again, and the rows of keptTables are carried
// across, in one transaction. PostgreSQL's DDL is transactional, so another
// instance sees the old database or the new one and never a table missing,
// and a reset that fails partway changes nothing.
//
// The drop is the migrations' own down files, newest first, which
// TestPostgresMigrationsRunDownAndUpAgain holds to leaving nothing behind.
// schema_migrations is not theirs and is left alone: the database ends at the
// version it started at, which startup has already brought to this build's.
// The up files issue a new install id, as on SQLite.
//
// This is the reset an admin asks for by name. Startup never calls it: see
// ConnectToPostgres.
//
// The statements below are DDL with the table name built in, from keptTables,
// and migration files run whole; sqlc can express neither.
func resetPostgres(sqlDB *sql.DB) error {
	ctx := context.Background()
	migrationSource, err := iofs.New(postgresMigrations, "migrations_postgres")
	if err != nil {
		return fmt.Errorf("failed to open the embedded PostgreSQL migrations: %w", err)
	}
	defer migrationSource.Close()
	versions, err := migrationVersions(migrationSource)
	if err != nil {
		return err
	}

	tx, err := sqlDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin the reset: %w", err)
	}
	// A no-op once Commit has run.
	defer tx.Rollback()

	kept := make([]string, 0, len(keptTables))
	for _, table := range keptTables {
		var exists bool
		if err := tx.QueryRowContext(ctx,
			`SELECT to_regclass(quote_ident(current_schema()) || '.' || quote_ident($1)) IS NOT NULL`, table,
		).Scan(&exists); err != nil {
			return fmt.Errorf("failed to look for %s: %w", table, err)
		}
		if !exists {
			continue
		}
		if _, err := tx.ExecContext(ctx,
			fmt.Sprintf(`CREATE TEMP TABLE "kept_%s" ON COMMIT DROP AS SELECT * FROM "%s"`, table, table),
		); err != nil {
			return fmt.Errorf("failed to set aside %s: %w", table, err)
		}
		kept = append(kept, table)
	}

	for _, version := range slices.Backward(versions) {
		if err := runMigration(ctx, tx, version, migrationSource.ReadDown); err != nil {
			return fmt.Errorf("failed to drop what migration %d made: %w", version, err)
		}
	}
	for _, version := range versions {
		if err := runMigration(ctx, tx, version, migrationSource.ReadUp); err != nil {
			return fmt.Errorf("failed to re-run migration %d: %w", version, err)
		}
	}

	for _, table := range kept {
		if _, err := tx.ExecContext(ctx,
			fmt.Sprintf(`INSERT INTO "%s" SELECT * FROM "kept_%s"`, table, table),
		); err != nil {
			return fmt.Errorf("failed to restore %s: %w", table, err)
		}
		if err := advanceIdentities(ctx, tx, table); err != nil {
			return fmt.Errorf("failed to restore the id sequence of %s: %w", table, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit the reset: %w", err)
	}
	return nil
}

// migrationVersions lists the versions in a migration source, oldest first.
func migrationVersions(migrationSource source.Driver) ([]uint, error) {
	version, err := migrationSource.First()
	if err != nil {
		return nil, fmt.Errorf("failed to find the first migration: %w", err)
	}
	versions := []uint{version}
	for {
		next, err := migrationSource.Next(version)
		if errors.Is(err, fs.ErrNotExist) {
			return versions, nil
		}
		if err != nil {
			return nil, fmt.Errorf("failed to find the migration after %d: %w", version, err)
		}
		versions = append(versions, next)
		version = next
	}
}

// runMigration runs one direction of a migration inside tx. read is the
// source's ReadUp or ReadDown.
func runMigration(ctx context.Context, tx *sql.Tx, version uint, read func(uint) (io.ReadCloser, string, error)) error {
	body, _, err := read(version)
	if err != nil {
		return err
	}
	// A migration is a file embedded in this binary, so reading it whole is
	// bounded by us.
	statements, err := io.ReadAll(body)
	if err := errors.Join(err, body.Close()); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, string(statements))
	return err
}

// identityTx is what advanceIdentities runs on: the reset's *sql.Tx, or the
// *sql.Conn MoveToPostgres holds its transaction on.
type identityTx interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// advanceIdentities moves each identity sequence of table past the rows just
// copied into it with their ids. PostgreSQL does not do that for an explicit
// id, and the next insert would otherwise be handed an id a restored row
// holds.
func advanceIdentities(ctx context.Context, tx identityTx, table string) error {
	rows, err := tx.QueryContext(ctx, `
		SELECT column_name FROM information_schema.columns
		WHERE table_schema = current_schema() AND table_name = $1 AND is_identity = 'YES'`, table)
	if err != nil {
		return err
	}
	columns := []string{}
	for rows.Next() {
		var column string
		if err := rows.Scan(&column); err != nil {
			rows.Close()
			return err
		}
		columns = append(columns, column)
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return err
	}
	for _, column := range columns {
		// With no rows the sequence is set so that the first id is again 1.
		if _, err := tx.ExecContext(ctx, fmt.Sprintf(
			`SELECT setval(pg_get_serial_sequence('%s', '%s'), COALESCE(MAX("%s"), 1), MAX("%s") IS NOT NULL) FROM "%s"`,
			table, column, column, column, table,
		)); err != nil {
			return err
		}
	}
	return nil
}
