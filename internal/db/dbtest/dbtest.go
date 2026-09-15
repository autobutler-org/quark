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
	"database/sql"
	"path/filepath"
	"testing"
	"time"

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
