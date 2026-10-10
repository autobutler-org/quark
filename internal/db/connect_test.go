package db

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"
)

// slowQuery counts far enough to outlast any test that starts it; the tests
// cancel it rather than wait.
const slowQuery = "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x < 2000000000) SELECT count(*) FROM c"

func newPooledQueries(t *testing.T) *Queries {
	t.Helper()
	sqlDB, err := sql.Open("sqlite", DSN(filepath.Join(t.TempDir(), "quark.db")))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	t.Cleanup(func() { sqlDB.Close() })
	return pooledQueries(sqlDB)
}

// One slow query must not hold up every other request's reads (#2766). On the
// single shared connection each statement waited its turn, so an
// authenticated request's session lookup queued behind whatever was running.
func TestPooledQueries_SlowQueryDoesNotBlockOtherReaders(t *testing.T) {
	conn := newPooledQueries(t).db

	ctx, cancel := context.WithCancel(context.Background())
	slowDone := make(chan error, 1)
	go func() {
		var n int64
		slowDone <- conn.QueryRowContext(ctx, slowQuery).Scan(&n)
	}()
	// Give the slow query time to be the statement in flight.
	time.Sleep(50 * time.Millisecond)

	read := make(chan error, 1)
	go func() {
		var one int
		read <- conn.QueryRowContext(context.Background(), "SELECT 1").Scan(&one)
	}()
	select {
	case err := <-read:
		if err != nil {
			t.Errorf("read beside a slow query: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Error("a read waited behind another request's slow query")
	}

	// The slow query's caller goes away, and its query goes with it instead
	// of running to the end for nobody.
	cancel()
	select {
	case err := <-slowDone:
		if err == nil {
			t.Error("the canceled query ran to completion")
		}
	case <-time.After(5 * time.Second):
		t.Error("the canceled query kept running")
	}
}

// A request that goes away mid-query must not fail the queries other requests
// are running (#2743). The driver answers a canceled context with
// sqlite3_interrupt, which interrupts every statement on the connection. On a
// pool the canceled caller has its connection to itself, so nobody else sees
// the interrupt, where on one shared connection it turned a client dropping
// its requests into a burst of 401s for everyone else.
func TestPooledQueries_CanceledQueryDoesNotInterruptOthers(t *testing.T) {
	conn := newPooledQueries(t).db

	// Another request part way through reading its rows.
	held, err := conn.QueryContext(context.Background(), "SELECT 1 UNION ALL SELECT 2")
	if err != nil {
		t.Fatalf("hold rows: %v", err)
	}
	defer held.Close()
	if !held.Next() {
		t.Fatalf("held rows returned nothing: %v", held.Err())
	}

	// A request whose client disconnects while its query runs.
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	var n int64
	if err := conn.QueryRowContext(ctx, slowQuery).Scan(&n); err == nil {
		t.Error("the canceled query ran to completion")
	}

	// Neither the held rows nor a new request may see the interrupt.
	var one int
	if err := conn.QueryRowContext(context.Background(), "SELECT 1").Scan(&one); err != nil {
		t.Errorf("a new query failed after another request was canceled: %v", err)
	}
	if !held.Next() {
		t.Errorf("held rows failed after another request was canceled: %v", held.Err())
	}
}
