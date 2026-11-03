// Package dbtest opens a real Quark database for a test.
//
// It exists to stop tests from hand-writing their own copy of the schema. A
// copy drifts: it keeps columns the migrations dropped, misses the ones they
// added, and — because a hand-written CREATE TABLE is usually trimmed to the
// two tables the test touches — quietly omits the foreign keys that make the
// real schema behave the way it does. A test that passes against a schema
// nothing runs in production is not evidence.
package dbtest

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"testing"
	"time"

	// Registers the "pgx" driver PostgresURL makes its schema with.
	_ "github.com/jackc/pgx/v5/stdlib"
	"golang.org/x/crypto/bcrypt"
	// Registers the "sqlite" driver these connections use.
	_ "modernc.org/sqlite"

	"github.com/autobutler-org/quark/internal/db"
)

// NewDB returns a database with the real embedded migration set applied,
// opened through db.DSN so it carries the timestamp format and the foreign key
// enforcement production runs with. The file lives in the test's temporary
// directory and the handle is closed when the test ends.
//
// The returned value carries both halves callers need: Db for raw SQL and
// Queries for the generated ones.
func NewDB(t testing.TB) *db.DatabaseSqlc {
	t.Helper()

	// A file rather than :memory:, because database/sql pools connections and
	// every connection to :memory: gets a database of its own — the migrations
	// would land somewhere the queries never look.
	sqlDB, err := sql.Open("sqlite", db.DSN(filepath.Join(t.TempDir(), "quark.db")))
	if err != nil {
		t.Fatalf("dbtest: open database: %v", err)
	}
	// Close does not wait for a connection still in use, such as a goroutine the
	// code under test started and did not join. Wait for it here, or it writes
	// the journal while t.TempDir's cleanup is removing the directory.
	t.Cleanup(func() {
		sqlDB.Close()
		deadline := time.Now().Add(10 * time.Second)
		for sqlDB.Stats().OpenConnections > 0 && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
	})

	database := &db.DatabaseSqlc{Db: sqlDB, Queries: db.NewQueries(sqlDB)}
	// The file is empty, so the drop half is a no-op and this is just "run
	// every migration" — the same schema production boots with.
	if err := db.ResetDatabase(database); err != nil {
		t.Fatalf("dbtest: apply migrations: %v", err)
	}
	return database
}

// PostgresURL returns the URL of an empty PostgreSQL schema of the test's own,
// on the database the Makefile's DB_BACKEND switch names, and drops the schema
// when the test ends. Open it with db.ConnectToPostgres, which migrates it.
//
// On the default backend the test is skipped by name. With the backend set
// to postgres a database that cannot be reached fails the test: a PostgreSQL
// check that quietly did not run would read as a pass.
func PostgresURL(t *testing.T) string {
	t.Helper()
	if os.Getenv(db.BackendEnv) != string(db.Postgres) {
		t.Skip("PostgreSQL only: run `make test/db/postgres`, or any backend test target with DB_BACKEND=postgres")
	}
	databaseURL, err := url.Parse(os.Getenv(db.DatabaseURLEnv))
	if err != nil || databaseURL.Host == "" {
		t.Fatalf("%s=postgres but %s is not a database URL (%v). Run the tests through make, which sets both: `make test/db/postgres`",
			db.BackendEnv, db.DatabaseURLEnv, err)
	}
	admin, err := sql.Open("pgx", databaseURL.String())
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := admin.PingContext(ctx); err != nil {
		admin.Close()
		t.Fatalf("no PostgreSQL answers at %s (%v). Run `make serve/postgres`, then run this again", databaseURL.Host, err)
	}

	var suffix [8]byte
	_, _ = rand.Read(suffix[:])
	schema := "quark_test_" + hex.EncodeToString(suffix[:])
	if _, err := admin.Exec("CREATE SCHEMA " + schema); err != nil {
		admin.Close()
		t.Fatalf("dbtest: create schema %s: %v", schema, err)
	}
	t.Cleanup(func() {
		if _, err := admin.Exec("DROP SCHEMA " + schema + " CASCADE"); err != nil {
			t.Errorf("dbtest: drop schema %s: %v", schema, err)
		}
		admin.Close()
	})
	query := databaseURL.Query()
	query.Set("search_path", schema)
	databaseURL.RawQuery = query.Encode()
	return databaseURL.String()
}

// AuthKey is the auth key a test's account signs in with in place of secret
// (#2430): the standard base64 of SHA-256(secret), 32 bytes like the key a
// client derives. It is not the client's derivation, only a stable stand-in,
// so two different secrets give two different keys.
func AuthKey(secret string) string {
	sum := sha256.Sum256([]byte(secret))
	return base64.StdEncoding.EncodeToString(sum[:])
}

// BcryptHash is the bcrypt hash of secret, for seeding a row no code writes
// any more: the password or recovery phrase hash of an account from before
// auth keys (#2430), or a key hash from before keys took SHA-256 (#2765). It
// hashes at bcrypt.MinCost, since cost 12 (~250ms a hash) made the auth
// suites take most of a minute each (#2456).
func BcryptHash(t *testing.T, secret string) string {
	t.Helper()
	hash, err := bcrypt.GenerateFromPassword([]byte(secret), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("dbtest: bcrypt: %v", err)
	}
	return string(hash)
}

// HideTable renames table out from under its queries and returns the function
// that puts it back with every row it held. It is how a test gets a real
// query error from one table while the rest of the schema keeps answering,
// and then shows that nothing was lost once the database answers again.
func HideTable(t *testing.T, sqlDB *sql.DB, table string) (restore func()) {
	t.Helper()
	if _, err := sqlDB.Exec("ALTER TABLE " + table + " RENAME TO " + table + "_hidden"); err != nil {
		t.Fatalf("dbtest: hide %s: %v", table, err)
	}
	return func() {
		t.Helper()
		if _, err := sqlDB.Exec("ALTER TABLE " + table + "_hidden RENAME TO " + table); err != nil {
			t.Fatalf("dbtest: restore %s: %v", table, err)
		}
	}
}

// SaltSecret stands in for the install's salt secret, which settingsutil keeps
// in the settings table, so an account a test makes with an auth key gets the same
// salt on every run.
func SaltSecret() ([]byte, error) {
	return []byte("dbtest salt secret, 32 bytes...."), nil
}

var (
	// generatedQuery matches one statement constant in a file sqlc generated.
	generatedQuery = regexp.MustCompile("(?s)const \\w+ = `-- name: (\\w+) :\\w+\n(.*?)`")
	// slicePlaceholder is what sqlc.slice leaves for the generated method to
	// expand at call time; one placeholder is its shortest valid expansion.
	slicePlaceholder = regexp.MustCompile(`/\*SLICE:\w+\*/\?`)
)

// PrepareAll prepares every statement in the source of a file sqlc generated,
// and returns how many it found and one line per statement the database
// rejected. sqlc accepting a query is not the engine accepting it, so each
// engine's tests run this over their generated package.
func PrepareAll(database *sql.DB, source string) (checked int, failures []string) {
	for _, match := range generatedQuery.FindAllStringSubmatch(source, -1) {
		checked++
		stmt, err := database.Prepare(slicePlaceholder.ReplaceAllString(match[2], "?"))
		if err != nil {
			failures = append(failures, fmt.Sprintf("%s: %v", match[1], err))
			continue
		}
		_ = stmt.Close()
	}
	return checked, failures
}
