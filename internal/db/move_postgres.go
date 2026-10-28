package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
)

// MoveToPostgresParams names the two databases MoveToPostgres copies between.
type MoveToPostgresParams struct {
	// SQLitePath is the install's quark.db. It is opened read-only.
	SQLitePath string
	// PostgresURL is the database to fill. It carries a password, so it is
	// never logged or put in an error.
	PostgresURL string
}

// MovedTable is one table MoveToPostgres filled and the rows now in it.
type MovedTable struct {
	Table string
	Rows  int64
	// Rebuilt marks a table that was left empty because the server fills it
	// again from the files on disk; see rebuiltTables.
	Rebuilt bool
}

// MoveToPostgresResult reports what MoveToPostgres copied.
type MoveToPostgresResult struct {
	// Tables is every table filled, in the order they were copied.
	Tables  []MovedTable
	Elapsed time.Duration
}

// rebuiltTables are derived data that MoveToPostgres leaves empty rather than
// copies. file_content is the text extracted from every document for content
// search, and the server's startup backfill (backfillContentIndex) extracts
// it again from the files themselves, so copying it would only carry over
// what the index looked like on SQLite. SQLite's FTS5 tables over it and over
// music_tracks are not in the PostgreSQL schema at all (#2958).
var rebuiltTables = []string{"file_content"}

// moveTimeLayouts are the forms a SQLite DATETIME may hold as text: its own
// datetime('now') form, which _time_format=datetime writes too, and the forms
// a value written before #1650 or by hand may be in.
var moveTimeLayouts = []string{
	"2006-01-02 15:04:05",
	"2006-01-02 15:04:05.999999999",
	"2006-01-02 15:04:05.999999999-07:00",
	"2006-01-02 15:04:05.999999999 -0700 MST",
	time.RFC3339Nano,
	"2006-01-02T15:04:05",
	"2006-01-02",
}

// MoveToPostgres copies every row of the SQLite database at SQLitePath into
// the PostgreSQL database at PostgresURL, which it migrates first, and checks
// that each table holds as many rows as the SQLite one did.
//
// The SQLite file is opened read-only and never changed, so abandoning the
// move leaves the install able to start on SQLite as before. The copy into
// PostgreSQL is one transaction: a failed or interrupted run leaves no rows
// behind, and running it again is safe. A PostgreSQL database that already
// has an account in it is refused, so a second run after a successful one
// cannot overwrite what the server has written since.
//
// The SQL here is built from table and column names read from the catalog at
// run time, and COPY and TRUNCATE are outside what sqlc expresses.
func MoveToPostgres(ctx context.Context, params MoveToPostgresParams) (MoveToPostgresResult, error) {
	start := time.Now()
	source, err := openSQLiteForMove(params.SQLitePath)
	if err != nil {
		return MoveToPostgresResult{}, err
	}
	defer source.Close()
	if err := requireCurrentSQLite(source, params.SQLitePath); err != nil {
		return MoveToPostgresResult{}, err
	}

	config, err := pgx.ParseConfig(params.PostgresURL)
	if err != nil {
		// pgx blanks the password in what it quotes back.
		return MoveToPostgresResult{}, fmt.Errorf("not a PostgreSQL connection URL: %w", err)
	}
	config.RuntimeParams["timezone"] = "UTC"
	if err := migratePostgres(*config); err != nil {
		return MoveToPostgresResult{}, err
	}
	target := openPostgresPool(*config)
	defer target.Close()

	// One read transaction, so every table and every count comes from the same
	// snapshot of the SQLite file.
	sourceTx, err := source.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return MoveToPostgresResult{}, fmt.Errorf("failed to read %s: %w", params.SQLitePath, err)
	}
	defer sourceTx.Rollback()

	conn, err := target.Conn(ctx)
	if err != nil {
		return MoveToPostgresResult{}, fmt.Errorf("failed to connect to PostgreSQL: %w", err)
	}
	defer conn.Close()
	if _, err := conn.ExecContext(ctx, `BEGIN`); err != nil {
		return MoveToPostgresResult{}, fmt.Errorf("failed to begin the copy: %w", err)
	}
	committed := false
	defer func() {
		if !committed {
			// Not ctx: an interrupted run must still roll back.
			_, _ = conn.ExecContext(context.WithoutCancel(ctx), `ROLLBACK`)
		}
	}()

	tables, err := copyTables(ctx, sourceTx, conn)
	if err != nil {
		return MoveToPostgresResult{}, err
	}
	if _, err := conn.ExecContext(ctx, `COMMIT`); err != nil {
		return MoveToPostgresResult{}, fmt.Errorf("failed to commit the copy: %w", err)
	}
	committed = true
	return MoveToPostgresResult{Tables: tables, Elapsed: time.Since(start)}, nil
}

// openSQLiteForMove opens the SQLite file at path read-only. mode=ro is what
// keeps MoveToPostgres's promise that the file is never changed: the driver
// refuses every write, and a missing file is an error rather than a new one.
func openSQLiteForMove(path string) (*sql.DB, error) {
	if _, err := os.Stat(path); err != nil {
		return nil, fmt.Errorf("no SQLite database at %s (%w). Pass the install's quark.db with --sqlite, and run "+
			"as the user the service runs as (quark on a device), whose data directory holds it", path, err)
	}
	sqlDB, err := sql.Open("sqlite", DSN("file:"+path+"?mode=ro"))
	if err != nil {
		return nil, fmt.Errorf("failed to open %s: %w", path, err)
	}
	return sqlDB, nil
}

// requireCurrentSQLite refuses a SQLite database that is not at this build's
// newest migration. The PostgreSQL side is migrated to this build's schema,
// and the two sets only describe the same tables at the same number. Migrating
// the file here would break the promise to leave it alone, so the fix is to
// let the server do it.
func requireCurrentSQLite(sqlDB *sql.DB, path string) error {
	migrationSource, err := newMigrationSource()
	if err != nil {
		return err
	}
	defer migrationSource.Close()
	versions, err := migrationVersions(migrationSource)
	if err != nil {
		return err
	}
	latest := versions[len(versions)-1]
	var version uint
	var dirty bool
	if err := sqlDB.QueryRow(`SELECT version, dirty FROM schema_migrations LIMIT 1`).Scan(&version, &dirty); err != nil {
		return fmt.Errorf("%s has no schema version Quark can read (%w): is it a Quark database?", path, err)
	}
	if dirty || version != latest {
		return fmt.Errorf("%s is at schema version %d (dirty: %t), and this build moves version %d. Start this "+
			"build of Quark on SQLite once so it migrates the database, stop it, and run this again",
			path, version, dirty, latest)
	}
	return nil
}

// copyTables empties every table of the PostgreSQL schema on conn, which is
// inside a transaction, and copies each from source in an order that puts a
// referenced table before the tables referencing it. It returns the tables
// with their verified row counts.
func copyTables(ctx context.Context, source *sql.Tx, conn *sql.Conn) ([]MovedTable, error) {
	var accounts int64
	if err := conn.QueryRowContext(ctx, `SELECT COUNT(*) FROM users`).Scan(&accounts); err != nil {
		return nil, fmt.Errorf("failed to look for accounts in the PostgreSQL database: %w", err)
	}
	if accounts > 0 {
		return nil, fmt.Errorf("the PostgreSQL database already has %d account(s), so it is in use, perhaps by an "+
			"earlier move that finished. Nothing was changed. Point the move at an empty database", accounts)
	}

	tables, err := postgresTables(ctx, conn)
	if err != nil {
		return nil, err
	}
	quoted := make([]string, len(tables))
	for i, table := range tables {
		quoted[i] = pgx.Identifier{table}.Sanitize()
	}
	// The migrations seed rows (the install id, the everyone group, the default
	// calendar and chat channel); the SQLite file has its own.
	if _, err := conn.ExecContext(ctx, `TRUNCATE `+strings.Join(quoted, ", ")+` RESTART IDENTITY`); err != nil {
		return nil, fmt.Errorf("failed to empty the PostgreSQL tables: %w", err)
	}

	moved := make([]MovedTable, 0, len(tables))
	for _, table := range tables {
		rebuilt := slices.Contains(rebuiltTables, table)
		if !rebuilt {
			if err := copyTable(ctx, source, conn, table); err != nil {
				return nil, err
			}
			if err := advanceIdentities(ctx, conn, table); err != nil {
				return nil, fmt.Errorf("failed to move the id sequence of %s past its rows: %w", table, err)
			}
		}
		var want, got int64
		if !rebuilt {
			if err := source.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+pgx.Identifier{table}.Sanitize()).Scan(&want); err != nil {
				return nil, fmt.Errorf("failed to count %s in SQLite: %w", table, err)
			}
		}
		if err := conn.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+pgx.Identifier{table}.Sanitize()).Scan(&got); err != nil {
			return nil, fmt.Errorf("failed to count %s in PostgreSQL: %w", table, err)
		}
		if got != want {
			return nil, fmt.Errorf("%s has %d rows in SQLite but %d in PostgreSQL after the copy; nothing was "+
				"committed", table, want, got)
		}
		moved = append(moved, MovedTable{Table: table, Rows: got, Rebuilt: rebuilt})
	}
	return moved, nil
}

// postgresTables lists the schema's tables, schema_migrations aside, each
// after every table it references.
func postgresTables(ctx context.Context, conn *sql.Conn) ([]string, error) {
	rows, err := conn.QueryContext(ctx, `
		SELECT table_name FROM information_schema.tables
		WHERE table_schema = current_schema() AND table_type = 'BASE TABLE' AND table_name <> 'schema_migrations'`)
	if err != nil {
		return nil, fmt.Errorf("failed to list the PostgreSQL tables: %w", err)
	}
	tables, err := scanStrings(rows)
	if err != nil {
		return nil, fmt.Errorf("failed to list the PostgreSQL tables: %w", err)
	}

	rows, err = conn.QueryContext(ctx, `
		SELECT DISTINCT referencing.relname, referenced.relname
		FROM pg_constraint c
		JOIN pg_class referencing ON referencing.oid = c.conrelid
		JOIN pg_class referenced ON referenced.oid = c.confrelid
		JOIN pg_namespace n ON n.oid = c.connamespace
		WHERE c.contype = 'f' AND n.nspname = current_schema()`)
	if err != nil {
		return nil, fmt.Errorf("failed to read the PostgreSQL foreign keys: %w", err)
	}
	references := map[string][]string{}
	for rows.Next() {
		var from, to string
		if err := rows.Scan(&from, &to); err != nil {
			rows.Close()
			return nil, err
		}
		references[from] = append(references[from], to)
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, fmt.Errorf("failed to read the PostgreSQL foreign keys: %w", err)
	}
	return dependencyOrder(tables, references)
}

// dependencyOrder sorts tables so each comes after every table it references,
// alphabetically among those free to go next. A table referencing itself
// (an album's parent album) is no constraint on the order: its rows arrive in
// one COPY, and PostgreSQL checks a foreign key at the end of the statement.
func dependencyOrder(tables []string, references map[string][]string) ([]string, error) {
	remaining := slices.Sorted(slices.Values(tables))
	ordered := make([]string, 0, len(tables))
	for len(remaining) > 0 {
		next := slices.IndexFunc(remaining, func(table string) bool {
			for _, referenced := range references[table] {
				if referenced != table && slices.Contains(remaining, referenced) {
					return false
				}
			}
			return true
		})
		if next < 0 {
			return nil, fmt.Errorf("the foreign keys among %s form a cycle, so no copy order satisfies them",
				strings.Join(remaining, ", "))
		}
		ordered = append(ordered, remaining[next])
		remaining = slices.Delete(remaining, next, next+1)
	}
	return ordered, nil
}

// copyTable streams table's rows out of SQLite and into PostgreSQL with COPY,
// one row in memory at a time, converting each value to its PostgreSQL column's
// type.
func copyTable(ctx context.Context, source *sql.Tx, conn *sql.Conn, table string) error {
	rows, err := conn.QueryContext(ctx, `
		SELECT column_name, data_type FROM information_schema.columns
		WHERE table_schema = current_schema() AND table_name = $1 AND is_generated = 'NEVER'
		ORDER BY ordinal_position`, table)
	if err != nil {
		return fmt.Errorf("failed to read the columns of %s: %w", table, err)
	}
	var columns, types, quoted []string
	for rows.Next() {
		var column, dataType string
		if err := rows.Scan(&column, &dataType); err != nil {
			rows.Close()
			return err
		}
		columns = append(columns, column)
		types = append(types, dataType)
		quoted = append(quoted, pgx.Identifier{column}.Sanitize())
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return fmt.Errorf("failed to read the columns of %s: %w", table, err)
	}

	sourceRows, err := source.QueryContext(ctx,
		`SELECT `+strings.Join(quoted, ", ")+` FROM `+pgx.Identifier{table}.Sanitize())
	if err != nil {
		return fmt.Errorf("failed to read %s from SQLite: %w", table, err)
	}
	defer sourceRows.Close()
	values := make([]any, len(columns))
	pointers := make([]any, len(columns))
	for i := range values {
		pointers[i] = &values[i]
	}
	next := func() ([]any, error) {
		if !sourceRows.Next() {
			return nil, sourceRows.Err()
		}
		if err := sourceRows.Scan(pointers...); err != nil {
			return nil, err
		}
		row := make([]any, len(values))
		for i, value := range values {
			converted, err := convertForPostgres(value, types[i])
			if err != nil {
				return nil, fmt.Errorf("%s.%s: %w", table, columns[i], err)
			}
			row[i] = converted
		}
		return row, nil
	}
	return conn.Raw(func(driverConn any) error {
		_, err := driverConn.(*stdlib.Conn).Conn().CopyFrom(ctx, pgx.Identifier{table}, columns, pgx.CopyFromFunc(next))
		if err != nil {
			return fmt.Errorf("failed to copy %s: %w", table, err)
		}
		return nil
	})
}

// convertForPostgres turns a value read from SQLite into what a PostgreSQL
// column of dataType (information_schema's name for it) takes. SQLite stores
// any value in any column, and the driver hands back what was stored: a
// DATETIME as a time.Time or as text, a flag as an integer.
func convertForPostgres(value any, dataType string) (any, error) {
	if value == nil {
		return nil, nil
	}
	switch dataType {
	case "timestamp with time zone":
		switch v := value.(type) {
		case time.Time:
			return v.UTC(), nil
		case string:
			for _, layout := range moveTimeLayouts {
				if t, err := time.ParseInLocation(layout, v, time.UTC); err == nil {
					return t.UTC(), nil
				}
			}
			return nil, fmt.Errorf("%q is not a time SQLite writes", v)
		}
	case "boolean":
		switch v := value.(type) {
		case bool:
			return v, nil
		case int64:
			return v != 0, nil
		}
	case "bigint":
		if v, ok := value.(int64); ok {
			return v, nil
		}
	case "double precision":
		switch v := value.(type) {
		case float64:
			return v, nil
		case int64:
			return float64(v), nil
		}
	case "bytea":
		switch v := value.(type) {
		case []byte:
			return v, nil
		case string:
			return []byte(v), nil
		}
	case "text":
		switch v := value.(type) {
		case string:
			return v, nil
		case []byte:
			return string(v), nil
		case int64:
			return strconv.FormatInt(v, 10), nil
		case float64:
			return strconv.FormatFloat(v, 'g', -1, 64), nil
		}
	}
	return nil, fmt.Errorf("cannot store a %T (%v) in a %s column", value, value, dataType)
}

// scanStrings reads one text column from every row and closes rows.
func scanStrings(rows *sql.Rows) ([]string, error) {
	values := []string{}
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			rows.Close()
			return nil, err
		}
		values = append(values, value)
	}
	return values, errors.Join(rows.Err(), rows.Close())
}
