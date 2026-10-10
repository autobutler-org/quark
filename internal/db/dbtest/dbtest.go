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
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"path/filepath"
	"testing"
	"time"

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
func NewDB(t *testing.T) *db.DatabaseSqlc {
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

	database := &db.DatabaseSqlc{Db: sqlDB, Queries: db.New(sqlDB)}
	// The file is empty, so the drop half is a no-op and this is just "run
	// every migration" — the same schema production boots with.
	if err := db.ResetDatabase(database); err != nil {
		t.Fatalf("dbtest: apply migrations: %v", err)
	}
	return database
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
