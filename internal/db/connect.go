package db

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func ConnectToDatabase() (*DatabaseSqlc, error) {
	var database DatabaseSqlc
	dataDir := storageutil.GetDataDir()
	err := os.MkdirAll(dataDir, 0755)
	if err != nil {
		return nil, fmt.Errorf("failed to create data directory: %v", err)
	}

	dataFilePath := filepath.Join(dataDir, "quark.db")

	database.Db, err = sql.Open("sqlite", DSN(dataFilePath))
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %v", err)
	}
	database.Queries, err = sharedQueries(database.Db)
	if err != nil {
		return nil, fmt.Errorf("failed to get database connection: %v", err)
	}

	if err := initSchema(&database); err != nil {
		return nil, fmt.Errorf("failed to initialize database schema: %v", err)
	}

	return &database, nil
}

func ConnectToVaultDatabase(dbPath string) (*DatabaseSqlc, error) {
	if err := os.MkdirAll(filepath.Dir(dbPath), 0755); err != nil {
		return nil, fmt.Errorf("failed to create vault db directory: %v", err)
	}

	var database DatabaseSqlc
	var err error
	database.Db, err = sql.Open("sqlite", DSN(dbPath))
	if err != nil {
		return nil, fmt.Errorf("failed to open vault database: %v", err)
	}

	if err := InitVaultSchema(database.Db); err != nil {
		database.Db.Close()
		return nil, fmt.Errorf("failed to init vault schema: %v", err)
	}

	database.Queries, err = sharedQueries(database.Db)
	if err != nil {
		database.Db.Close()
		return nil, fmt.Errorf("failed to get vault db connection: %v", err)
	}

	return &database, nil
}

// sharedQueries binds Queries to one connection taken out of sqlDB, which every
// caller then shares.
//
// The connection never sees a caller's cancellation (#2743). The driver answers
// a canceled context with sqlite3_interrupt, and that interrupts the
// connection, not the one query: every statement running on it fails, and so
// does every statement prepared on it until none is left running. On a shared
// connection that turns one client going away into errors for every other
// request in flight — under load, a burst of 401s, since requireAuth cannot
// tell a failed session lookup from a bad token. A pooled connection would be
// checked and discarded after an interrupt; this one is never handed back, so
// it is never checked. Queries here are short, so a canceled caller just lets
// its query finish.
func sharedQueries(sqlDB *sql.DB) (*Queries, error) {
	sqlConn, err := sqlDB.Conn(context.Background())
	if err != nil {
		return nil, err
	}
	return New(detachedConn{sqlConn}), nil
}

// detachedConn runs every call on conn with the caller's context stripped of
// its cancellation and deadline, keeping its values.
type detachedConn struct{ conn *sql.Conn }

func (u detachedConn) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	return u.conn.ExecContext(context.WithoutCancel(ctx), query, args...)
}

func (u detachedConn) PrepareContext(ctx context.Context, query string) (*sql.Stmt, error) {
	return u.conn.PrepareContext(context.WithoutCancel(ctx), query)
}

func (u detachedConn) QueryContext(ctx context.Context, query string, args ...interface{}) (*sql.Rows, error) {
	return u.conn.QueryContext(context.WithoutCancel(ctx), query, args...)
}

func (u detachedConn) QueryRowContext(ctx context.Context, query string, args ...interface{}) *sql.Row {
	return u.conn.QueryRowContext(context.WithoutCancel(ctx), query, args...)
}

func ConnectToHealthDatabase() (*DatabaseRaw, error) {
	var database DatabaseRaw
	dataDir := storageutil.GetDataDir()
	err := os.MkdirAll(dataDir, 0755)
	if err != nil {
		panic(fmt.Sprintf("failed to create data directory: %v", err))
	}

	healthFilePath := filepath.Join(dataDir, "quark.health.db")

	// Initialize health database for OTEL traces (no migrations needed)
	database.Db, err = sql.Open("sqlite", DSN(healthFilePath))
	if err != nil {
		panic(fmt.Sprintf("failed to open health database: %v", err))
	}
	return &database, nil
}
