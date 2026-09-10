package dbtest_test

import (
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// The point of running the real migrations is that tests get the real
// constraints. If foreign keys were not enforced on this connection every test
// converted to NewDB would still pass while proving nothing, so assert it
// directly: an orphan insert must be rejected, and a cascade must run.
func TestNewDBEnforcesForeignKeys(t *testing.T) {
	database := dbtest.NewDB(t)

	if _, err := database.Db.Exec(
		`INSERT INTO sessions (token, user_id, expires_at) VALUES ('t', 999, datetime('now'))`,
	); err == nil {
		t.Fatal("inserted a session for a user that does not exist")
	}

	if _, err := database.Db.Exec(
		`INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES ('u', 'h', 'r')`,
	); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if _, err := database.Db.Exec(
		`INSERT INTO sessions (token, user_id, expires_at)
		 SELECT 't', id, datetime('now') FROM users WHERE username = 'u'`,
	); err != nil {
		t.Fatalf("insert session: %v", err)
	}
	if _, err := database.Db.Exec(`DELETE FROM users WHERE username = 'u'`); err != nil {
		t.Fatalf("delete user: %v", err)
	}

	var sessions int
	if err := database.Db.QueryRow(`SELECT COUNT(*) FROM sessions`).Scan(&sessions); err != nil {
		t.Fatalf("count sessions: %v", err)
	}
	if sessions != 0 {
		t.Fatalf("ON DELETE CASCADE did not run: %d sessions left", sessions)
	}
}

// Quark writes from background goroutines while requests are being served —
// trackDevice's connected_devices upsert is the busiest of them. SQLite allows
// one writer at a time, and with no busy handler armed the loser of that race
// gets SQLITE_BUSY immediately; requireAuth cannot tell that from a bad token,
// so it answered 401 and logged the client out. The DSN's busy_timeout is what
// makes the loser wait instead, so assert it is actually armed: a second writer
// must block until the first commits rather than fail on the spot.
func TestNewDBWaitsOutABusyWriter(t *testing.T) {
	database := dbtest.NewDB(t)

	holder, err := database.Db.Begin()
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	if _, err := holder.Exec(
		`INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES ('holder', 'h', 'r')`,
	); err != nil {
		t.Fatalf("holder insert: %v", err)
	}

	released := make(chan struct{})
	go func() {
		time.Sleep(200 * time.Millisecond)
		close(released)
		if err := holder.Commit(); err != nil {
			t.Errorf("holder commit: %v", err)
		}
	}()

	// Without busy_timeout this returns SQLITE_BUSY before `released` is closed.
	if _, err := database.Db.Exec(
		`INSERT INTO users (username, password_hash, recovery_phrase_hash) VALUES ('waiter', 'h', 'r')`,
	); err != nil {
		t.Fatalf("second writer did not wait out the first: %v", err)
	}
	select {
	case <-released:
	default:
		t.Fatal("second writer returned before the first released the lock")
	}
}
