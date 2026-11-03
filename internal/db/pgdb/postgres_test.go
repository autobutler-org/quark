package pgdb_test

import (
	"database/sql"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	// Registers the "pgx" database/sql driver these tests connect with.
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// migrationsDir is the PostgreSQL migration set, from this package.
const migrationsDir = "../migrations_postgres"

// migrations returns the PostgreSQL migrations in one direction, in the order
// that direction applies them.
func migrations(t *testing.T, direction string) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(migrationsDir, "*."+direction+".sql"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no %s migrations in %s: %v", direction, migrationsDir, err)
	}
	sort.Strings(files)
	if direction == "down" {
		sort.Sort(sort.Reverse(sort.StringSlice(files)))
	}
	return files
}

// migrate runs the PostgreSQL migrations in one direction.
func migrate(t *testing.T, conn *sql.DB, direction string) {
	t.Helper()
	for _, file := range migrations(t, direction) {
		statements, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := conn.Exec(string(statements)); err != nil {
			t.Fatalf("apply %s: %v", file, err)
		}
	}
}

// openPostgres returns a connection to an empty schema of the test's own
// (dbtest.PostgresURL) with the PostgreSQL migrations applied by hand, so
// that the tests here can also run them down.
func openPostgres(t *testing.T) *sql.DB {
	t.Helper()
	conn, err := sql.Open("pgx", dbtest.PostgresURL(t))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	migrate(t, conn, "up")
	return conn
}

// sqlc accepting a query is not PostgreSQL accepting it: sqlc does not check
// operand types, and it knows a function only by the name the schema gave it.
// Preparing every generated statement on a real server with the schema
// applied is what holds the shared queries to the rules in
// sql/queries/AGENTS.md.
func TestEveryGeneratedQueryPreparesOnPostgres(t *testing.T) {
	conn := openPostgres(t)
	files, err := filepath.Glob("*.sql.go")
	if err != nil || len(files) == 0 {
		t.Fatalf("no generated query files found: %v", err)
	}
	total := 0
	for _, file := range files {
		source, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		checked, failures := dbtest.PrepareAll(conn, string(source))
		total += checked
		for _, failure := range failures {
			t.Errorf("%s: %s", file, failure)
		}
	}
	if total == 0 {
		t.Fatal("found no statements in the generated files; dbtest.PrepareAll no longer matches sqlc's output")
	}
	t.Logf("prepared %d statements", total)
}

// The check above is only worth having if it can fail on what PostgreSQL
// alone refuses: a text column compared with a number is fine on SQLite.
func TestPrepareAllReportsWhatPostgresRejects(t *testing.T) {
	source := "const good = `-- name: Good :one\nSELECT install_id FROM install WHERE id = $1\n`\n" +
		"const mistyped = `-- name: Mistyped :many\nSELECT id FROM jobs WHERE status = 1\n`\n" +
		"const noFunction = `-- name: NoFunction :one\nSELECT instr('abc', 'b')\n`\n"
	checked, failures := dbtest.PrepareAll(openPostgres(t), source)
	if checked != 3 || len(failures) != 2 {
		t.Fatalf("checked %d statements with failures %q, want 3 checked and Mistyped and NoFunction rejected", checked, failures)
	}
}

// column is what the two schemas have to agree on for one column.
type column struct {
	Name     string
	Type     string
	Nullable bool
}

// postgresType is the type-mapping table in internal/db/AGENTS.md, as
// information_schema spells the PostgreSQL side.
var postgresType = map[string]string{
	"INTEGER":  "bigint",
	"BOOLEAN":  "boolean",
	"DATETIME": "timestamp with time zone",
	"REAL":     "double precision",
	"BLOB":     "bytea",
	"TEXT":     "text",
}

// The PostgreSQL schema is written by hand beside the SQLite one. This holds
// it to the same tables and, column for column, the same order, nullability
// and mapped type, which is what gives sqlc identical Go types on both sides.
// Indexes, defaults and constraints are not compared here.
func TestPostgresSchemaMatchesSQLite(t *testing.T) {
	postgres := openPostgres(t)
	sqlite := dbtest.NewDB(t).Db

	want := map[string][]column{}
	// FTS5 virtual tables and the shadow tables SQLite creates beside them are
	// not in the PostgreSQL schema. A new one has to be named here:
	// file_content_fts (content search, whose PostgreSQL counterpart is the
	// search_vector column skipped below), music_tracks_fts (music search) and
	// file_index_fts (filename search, which reads file_index directly there).
	tables, err := sqlite.Query(`SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
		AND name != 'schema_migrations' AND name NOT LIKE 'file_content_fts%' AND name NOT LIKE 'music_tracks_fts%'
		AND name NOT LIKE 'file_index_fts%'`)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for tables.Next() {
		var name string
		if err := tables.Scan(&name); err != nil {
			t.Fatal(err)
		}
		names = append(names, name)
	}
	tables.Close()
	for _, name := range names {
		rows, err := sqlite.Query(`SELECT name, type, "notnull", pk FROM pragma_table_info(?) ORDER BY cid`, name)
		if err != nil {
			t.Fatal(err)
		}
		for rows.Next() {
			var col column
			var notNull, primaryKey int
			if err := rows.Scan(&col.Name, &col.Type, &notNull, &primaryKey); err != nil {
				t.Fatal(err)
			}
			mapped, ok := postgresType[strings.ToUpper(col.Type)]
			if !ok {
				t.Errorf("%s.%s has SQLite type %q, which internal/db/AGENTS.md has no PostgreSQL mapping for", name, col.Name, col.Type)
			}
			// SQLite reports a primary key column as nullable unless it says NOT NULL; it never holds NULL here.
			want[name] = append(want[name], column{Name: col.Name, Type: mapped, Nullable: notNull == 0 && primaryKey == 0})
		}
		rows.Close()
	}

	got := map[string][]column{}
	rows, err := postgres.Query(`SELECT table_name, column_name, data_type, is_nullable = 'YES'
		FROM information_schema.columns WHERE table_schema = current_schema() ORDER BY table_name, ordinal_position`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var table string
		var col column
		if err := rows.Scan(&table, &col.Name, &col.Type, &col.Nullable); err != nil {
			t.Fatal(err)
		}
		// PostgreSQL's counterpart of file_content_fts is a generated column
		// on file_content itself (041_content_search). No query reads it.
		if table == "file_content" && col.Name == "search_vector" {
			continue
		}
		got[table] = append(got[table], col)
	}

	for table, columns := range want {
		if !reflect.DeepEqual(got[table], columns) {
			t.Errorf("table %s:\n  PostgreSQL has %+v\n  SQLite needs  %+v", table, got[table], columns)
		}
	}
	for table := range got {
		if _, ok := want[table]; !ok {
			t.Errorf("PostgreSQL has a table %s that SQLite does not", table)
		}
	}
}

// The down migrations leave nothing behind, and the schema comes back after.
func TestPostgresMigrationsRunDownAndUpAgain(t *testing.T) {
	conn := openPostgres(t)
	migrate(t, conn, "down")
	var left int
	if err := conn.QueryRow(`SELECT
		(SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = current_schema())
		+ (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = current_schema())`).Scan(&left); err != nil {
		t.Fatal(err)
	}
	if left != 0 {
		t.Errorf("the down migrations left %d tables and functions behind", left)
	}
	migrate(t, conn, "up")
}

// The functions the migrations define under SQLite's names: the forms the
// shared queries use, and a refusal for a form they do not implement.
func TestSQLiteNamedFunctions(t *testing.T) {
	conn := openPostgres(t)

	var ago, now time.Time
	if err := conn.QueryRow(`SELECT datetime('now', '-' || CAST($1 AS BIGINT) || ' seconds'), CURRENT_TIMESTAMP`, 90).Scan(&ago, &now); err != nil {
		t.Fatalf("datetime('now', '-90 seconds'): %v", err)
	}
	if got := now.Sub(ago); got != 90*time.Second {
		t.Errorf("datetime('now', '-90 seconds') is %v before CURRENT_TIMESTAMP, want 1m30s", got)
	}
	if err := conn.QueryRow(`SELECT datetime('2026-01-01 00:00:00', '-90 seconds')`).Scan(&ago); err == nil {
		t.Error("datetime() accepted a base other than 'now'")
	}

	var stamped time.Time
	if err := conn.QueryRow(`SELECT strftime('%Y-%m-%d %H:%M:%f', 'now'), CURRENT_TIMESTAMP`).Scan(&stamped, &now); err != nil {
		t.Fatalf("strftime('%%Y-%%m-%%d %%H:%%M:%%f', 'now'): %v", err)
	}
	if !stamped.Equal(now) {
		t.Errorf("strftime('%%Y-%%m-%%d %%H:%%M:%%f', 'now') = %v, want CURRENT_TIMESTAMP %v", stamped, now)
	}
	if err := conn.QueryRow(`SELECT strftime('%Y-%m-%d', 'now')`).Scan(&stamped); err == nil {
		t.Error("strftime() accepted a format other than milliseconds")
	}
	if err := conn.QueryRow(`SELECT strftime('%Y-%m-%d %H:%M:%f', '2026-01-01')`).Scan(&stamped); err == nil {
		t.Error("strftime() accepted a base other than 'now'")
	}

	for _, tc := range []struct {
		doc, path string
		want      sql.NullString
	}{
		{`{"targetDeviceSerial":"abc"}`, "$.targetDeviceSerial", sql.NullString{String: "abc", Valid: true}},
		{`{"a":{"b":5}}`, "$.a.b", sql.NullString{String: "5", Valid: true}},
		{`{"a":1}`, "$.missing", sql.NullString{}},
		{`{"a":null}`, "$.a", sql.NullString{}},
	} {
		var got sql.NullString
		if err := conn.QueryRow(`SELECT json_extract($1, $2)`, tc.doc, tc.path).Scan(&got); err != nil {
			t.Fatalf("json_extract(%s, %s): %v", tc.doc, tc.path, err)
		}
		if got != tc.want {
			t.Errorf("json_extract(%s, %s) = %+v, want %+v", tc.doc, tc.path, got, tc.want)
		}
	}

	for _, tc := range []struct {
		haystack, needle string
		want             int64
	}{
		{"photos 2024", "2024", 8},
		{"photos 2024", "", 1},
		{"日本語.txt", ".txt", 4},
		{"a%b_c", "%b_", 2},
		{"abc", "x", 0},
	} {
		var got int64
		if err := conn.QueryRow(`SELECT instr($1, $2)`, tc.haystack, tc.needle).Scan(&got); err != nil {
			t.Fatalf("instr(%q, %q): %v", tc.haystack, tc.needle, err)
		}
		if got != tc.want {
			t.Errorf("instr(%q, %q) = %d, want %d", tc.haystack, tc.needle, got, tc.want)
		}
	}
}
