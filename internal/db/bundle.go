package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// A bundle's database is a SQLite file at this build's schema, whichever
// engine it came from or goes to (#3838). SQLite is the format because it is
// one file that needs no server, and MoveToPostgres already fills PostgreSQL
// from one. ExportDatabase writes it, ImportDatabase reads it.
//
// The SQL here is built from table and column names read from the catalog at
// run time, which sqlc does not express.

// ExportDatabaseParams names the database to read and the file to write.
type ExportDatabaseParams struct {
	// Source is the database the install runs on.
	Source Config
	// SQLitePath is the install's quark.db, read when Source is SQLite. It is
	// opened read-only.
	SQLitePath string
	// Dest is the SQLite file to create. It must not exist yet.
	Dest string
}

// ImportDatabaseParams names a bundle's database and the install to fill.
type ImportDatabaseParams struct {
	// BundleDB is the database taken out of a bundle. It is migrated in place
	// to this build's schema, so pass a copy.
	BundleDB string
	// Target is the database the new install runs on.
	Target Config
	// SQLitePath is the new install's quark.db, used when Target is SQLite. It
	// is created when it does not exist.
	SQLitePath string
}

// CopyDatabaseResult is every table a bundle export or import filled, in the
// order it was copied, each with its row count, which matched the source's.
type CopyDatabaseResult struct {
	Tables  []MovedTable
	Elapsed time.Duration
}

// ExportDatabase copies every row of the install's database into a new SQLite
// file at Dest, in one read-only transaction on the source, and checks that
// every table ends with the source's row count. The source is not changed.
// Derived tables (rebuiltTables) are left empty.
func ExportDatabase(ctx context.Context, params ExportDatabaseParams) (CopyDatabaseResult, error) {
	start := time.Now()
	if _, err := os.Stat(params.Dest); err == nil {
		return CopyDatabaseResult{}, fmt.Errorf("%s already exists; the export writes a new file", params.Dest)
	}
	var source *sql.DB
	var options *sql.TxOptions
	name := params.SQLitePath
	if params.Source.Backend == Postgres {
		config, err := pgx.ParseConfig(params.Source.PostgresURL)
		if err != nil {
			// pgx blanks the password in what it quotes back.
			return CopyDatabaseResult{}, fmt.Errorf("not a PostgreSQL connection URL: %w", err)
		}
		config.RuntimeParams["timezone"] = "UTC"
		source = openPostgresPool(*config)
		name = "the PostgreSQL database"
		// One snapshot for every table and every count.
		options = &sql.TxOptions{ReadOnly: true, Isolation: sql.LevelRepeatableRead}
	} else {
		var err error
		if source, err = openSQLiteForMove(params.SQLitePath); err != nil {
			return CopyDatabaseResult{}, err
		}
		options = &sql.TxOptions{ReadOnly: true}
	}
	defer source.Close()
	if err := requireCurrentSchema(source, name, params.Source.Backend); err != nil {
		return CopyDatabaseResult{}, err
	}

	dest, err := openMigratedSQLite(params.Dest)
	if err != nil {
		return CopyDatabaseResult{}, err
	}
	defer dest.Close()
	tables, err := fillSQLite(ctx, source, options, dest)
	if err != nil {
		return CopyDatabaseResult{}, err
	}
	return CopyDatabaseResult{Tables: tables, Elapsed: time.Since(start)}, nil
}

// ImportDatabase fills a new install's database with the rows of a bundle's
// and checks that every table ends with the bundle's row count. Ids come back
// as they were. A target with an account is refused before anything on it
// changes, and the copy is one transaction, so a failed run leaves the target
// without accounts and running it again is safe.
func ImportDatabase(ctx context.Context, params ImportDatabaseParams) (CopyDatabaseResult, error) {
	start := time.Now()
	if err := RequireUninitialized(ctx, params.Target, params.SQLitePath); err != nil {
		return CopyDatabaseResult{}, err
	}
	// A bundle from an older build is brought up to this one.
	bundle, err := openMigratedSQLite(params.BundleDB)
	if err != nil {
		return CopyDatabaseResult{}, fmt.Errorf("the bundle's database: %w", err)
	}
	if err := bundle.Close(); err != nil {
		return CopyDatabaseResult{}, err
	}

	if params.Target.Backend == Postgres {
		moved, err := MoveToPostgres(ctx, MoveToPostgresParams{SQLitePath: params.BundleDB, PostgresURL: params.Target.PostgresURL})
		return CopyDatabaseResult{Tables: moved.Tables, Elapsed: time.Since(start)}, err
	}
	source, err := openSQLiteForMove(params.BundleDB)
	if err != nil {
		return CopyDatabaseResult{}, err
	}
	defer source.Close()
	target, err := openMigratedSQLite(params.SQLitePath)
	if err != nil {
		return CopyDatabaseResult{}, err
	}
	defer target.Close()
	tables, err := fillSQLite(ctx, source, &sql.TxOptions{ReadOnly: true}, target)
	if err != nil {
		return CopyDatabaseResult{}, err
	}
	return CopyDatabaseResult{Tables: tables, Elapsed: time.Since(start)}, nil
}

// RequireUninitialized returns an error when the install's database has an
// account in it. A database that does not exist yet, or has no users table,
// is uninitialized. It reads and never writes.
func RequireUninitialized(ctx context.Context, config Config, sqlitePath string) error {
	if config.Backend == Postgres {
		pgConfig, err := pgx.ParseConfig(config.PostgresURL)
		if err != nil {
			return fmt.Errorf("not a PostgreSQL connection URL: %w", err)
		}
		pool := openPostgresPool(*pgConfig)
		defer pool.Close()
		return refuseAccounts(ctx, pool)
	}
	if _, err := os.Stat(sqlitePath); errors.Is(err, os.ErrNotExist) {
		return nil
	}
	sqlDB, err := sql.Open("sqlite", DSN("file:"+sqlitePath+"?mode=ro"))
	if err != nil {
		return fmt.Errorf("failed to open %s: %w", sqlitePath, err)
	}
	defer sqlDB.Close()
	var hasUsers bool
	if err := sqlDB.QueryRowContext(ctx,
		`SELECT EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'users')`).Scan(&hasUsers); err != nil {
		return fmt.Errorf("failed to read %s: %w", sqlitePath, err)
	}
	if !hasUsers {
		return nil
	}
	return refuseSQLiteAccounts(ctx, sqlDB, sqlitePath)
}

// refuseSQLiteAccounts is RequireUninitialized's answer for a SQLite database
// with a users table, on a pool or inside fillSQLite's transaction.
func refuseSQLiteAccounts(ctx context.Context, target interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}, name string) error {
	var accounts int64
	if err := target.QueryRowContext(ctx, `SELECT COUNT(*) FROM users`).Scan(&accounts); err != nil {
		return fmt.Errorf("failed to look for accounts in %s: %w", name, err)
	}
	if accounts > 0 {
		return fmt.Errorf("%s already has %d account(s), so this Quark is in use, perhaps by an earlier import "+
			"that finished. Nothing was changed. Import into a new install, one nobody has signed up on yet",
			name, accounts)
	}
	return nil
}

// openMigratedSQLite opens the SQLite file at path, creating it when it does
// not exist, and brings it to this build's schema as the server's startup does.
func openMigratedSQLite(path string) (*sql.DB, error) {
	sqlDB, err := sql.Open("sqlite", DSN(path))
	if err != nil {
		return nil, fmt.Errorf("failed to open %s: %w", path, err)
	}
	if err := initSchema(&DatabaseSqlc{Db: sqlDB}); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("failed to bring %s to this build's schema: %w", path, err)
	}
	return sqlDB, nil
}

// fillSQLite replaces every row of the SQLite database target with source's,
// table by table, in one transaction on each side, and checks every table's
// count against source's. source may be either engine; its tables and columns
// are target's. Foreign keys are checked at the commit, so the tables go in
// any order. Rows pass through one at a time.
func fillSQLite(ctx context.Context, source *sql.DB, options *sql.TxOptions, target *sql.DB) ([]MovedTable, error) {
	sourceTx, err := source.BeginTx(ctx, options)
	if err != nil {
		return nil, fmt.Errorf("failed to begin reading the source: %w", err)
	}
	defer sourceTx.Rollback()

	conn, err := target.Conn(ctx)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	tables, err := sqliteTables(ctx, conn)
	if err != nil {
		return nil, err
	}
	if _, err := conn.ExecContext(ctx, `BEGIN IMMEDIATE`); err != nil {
		return nil, fmt.Errorf("failed to begin the copy: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			// Not ctx: an interrupted run must still roll back.
			_, _ = conn.ExecContext(context.WithoutCancel(ctx), `ROLLBACK`)
		}
	}()
	if _, err := conn.ExecContext(ctx, `PRAGMA defer_foreign_keys = ON`); err != nil {
		return nil, err
	}
	if err := refuseSQLiteAccounts(ctx, conn, "the target database"); err != nil {
		return nil, err
	}
	// Every table is emptied before any is filled: a parent's ON DELETE
	// CASCADE would otherwise take the rows already copied into its children.
	// This clears the rows the migrations seed, which the source has its own of.
	for _, table := range tables {
		if _, err := conn.ExecContext(ctx, `DELETE FROM `+pgx.Identifier{table}.Sanitize()); err != nil {
			return nil, fmt.Errorf("failed to empty %s: %w", table, err)
		}
	}

	moved := make([]MovedTable, 0, len(tables))
	for _, table := range tables {
		rebuilt := slices.Contains(rebuiltTables, table)
		var want int64
		if !rebuilt {
			if err := copyIntoSQLite(ctx, sourceTx, conn, table); err != nil {
				return nil, err
			}
			if err := sourceTx.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+pgx.Identifier{table}.Sanitize()).Scan(&want); err != nil {
				return nil, fmt.Errorf("failed to count %s in the source: %w", table, err)
			}
		}
		var got int64
		if err := conn.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+pgx.Identifier{table}.Sanitize()).Scan(&got); err != nil {
			return nil, fmt.Errorf("failed to count %s: %w", table, err)
		}
		if got != want {
			return nil, fmt.Errorf("%s has %d rows in the source but %d after the copy; nothing was committed",
				table, want, got)
		}
		moved = append(moved, MovedTable{Table: table, Rows: got, Rebuilt: rebuilt})
	}
	if _, err := conn.ExecContext(ctx, `COMMIT`); err != nil {
		return nil, fmt.Errorf("failed to commit the copy: %w", err)
	}
	committed = true
	return moved, nil
}

// sqliteTables lists conn's tables in name order, leaving out SQLite's own,
// schema_migrations, and FTS5's virtual and shadow tables, which their
// triggers fill as the rows arrive.
func sqliteTables(ctx context.Context, conn *sql.Conn) ([]string, error) {
	rows, err := conn.QueryContext(ctx, `
		SELECT name FROM pragma_table_list
		WHERE schema = 'main' AND type = 'table' AND name NOT LIKE 'sqlite\_%' ESCAPE '\'
			AND name <> 'schema_migrations'
		ORDER BY name`)
	if err != nil {
		return nil, fmt.Errorf("failed to list the SQLite tables: %w", err)
	}
	return scanStrings(rows)
}

// copyIntoSQLite copies table's rows from source into conn, by the columns
// conn's table has, one row in memory at a time.
func copyIntoSQLite(ctx context.Context, source *sql.Tx, conn *sql.Conn, table string) error {
	rows, err := conn.QueryContext(ctx, `SELECT name FROM pragma_table_xinfo(?) WHERE hidden = 0 ORDER BY cid`, table)
	if err != nil {
		return fmt.Errorf("failed to read the columns of %s: %w", table, err)
	}
	columns, err := scanStrings(rows)
	if err != nil {
		return fmt.Errorf("failed to read the columns of %s: %w", table, err)
	}
	quoted := make([]string, len(columns))
	for i, column := range columns {
		quoted[i] = pgx.Identifier{column}.Sanitize()
	}
	list := strings.Join(quoted, ", ")
	insert, err := conn.PrepareContext(ctx, `INSERT INTO `+pgx.Identifier{table}.Sanitize()+` (`+list+`) VALUES (?`+
		strings.Repeat(", ?", len(columns)-1)+`)`)
	if err != nil {
		return fmt.Errorf("failed to prepare the copy of %s: %w", table, err)
	}
	defer insert.Close()

	sourceRows, err := source.QueryContext(ctx, `SELECT `+list+` FROM `+pgx.Identifier{table}.Sanitize())
	if err != nil {
		return fmt.Errorf("failed to read %s from the source: %w", table, err)
	}
	defer sourceRows.Close()
	values := make([]any, len(columns))
	pointers := make([]any, len(columns))
	for i := range values {
		pointers[i] = &values[i]
	}
	for sourceRows.Next() {
		if err := sourceRows.Scan(pointers...); err != nil {
			return fmt.Errorf("failed to read %s from the source: %w", table, err)
		}
		for i, value := range values {
			// An empty blob scans as a nil slice, which would be written as
			// NULL. A SQL NULL is a nil value, not a nil slice.
			if blob, ok := value.([]byte); ok && blob == nil {
				values[i] = []byte{}
			}
		}
		if _, err := insert.ExecContext(ctx, values...); err != nil {
			return fmt.Errorf("failed to copy a row of %s: %w", table, err)
		}
	}
	if err := sourceRows.Err(); err != nil {
		return fmt.Errorf("failed to read %s from the source: %w", table, err)
	}
	return nil
}
