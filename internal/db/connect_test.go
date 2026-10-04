package db

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"
)

// A request that goes away mid-query must not fail the queries other requests
// are running on the shared connection (#2743). The driver answers a canceled
// context with sqlite3_interrupt, which interrupts every statement on the
// connection and keeps failing new ones until none is left running. Under load
// that turned a client dropping its requests into a burst of 401s for everyone
// else, because requireAuth cannot tell a failed session lookup from a bad
// token.
func TestSharedQueries_CanceledQueryDoesNotInterruptOthers(t *testing.T) {
	sqlDB, err := sql.Open("sqlite", DSN(filepath.Join(t.TempDir(), "quark.db")))
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	t.Cleanup(func() { sqlDB.Close() })
	queries, err := sharedQueries(sqlDB)
	if err != nil {
		t.Fatalf("sharedQueries: %v", err)
	}
	conn := queries.db

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
	_ = conn.QueryRowContext(ctx,
		"WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x < 1000000) SELECT count(*) FROM c",
	).Scan(&n)

	// Neither the held rows nor a new request may see the interrupt.
	var one int
	if err := conn.QueryRowContext(context.Background(), "SELECT 1").Scan(&one); err != nil {
		t.Errorf("a new query failed after another request was canceled: %v", err)
	}
	if !held.Next() {
		t.Errorf("held rows failed after another request was canceled: %v", held.Err())
	}
}
