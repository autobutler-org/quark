package db

import (
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
	database.Queries = pooledQueries(database.Db)

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

	database.Queries = pooledQueries(database.Db)

	return &database, nil
}

// maxOpenConns bounds the pool every sqlc query draws from. Each connection
// costs a file descriptor and its own page cache, and the device has four
// cores, so more connections than this only queue inside SQLite instead of
// inside database/sql.
const maxOpenConns = 16

// pooledQueries binds Queries to sqlDB's connection pool, bounded to
// maxOpenConns, so one request's query never waits for another's (#2766).
//
// A caller's cancellation reaches its query. The driver answers a canceled
// context with sqlite3_interrupt, which interrupts the connection rather than
// the one query (#2743); a pooled connection belongs to one caller until its
// statement or rows are done, so the interrupt fails nobody else, and a
// request whose client went away stops costing anything.
//
// The bound covers everything else that uses sqlDB too. A caller that holds
// one connection and asks for a second (a query run while iterating another's
// rows, or outside a transaction from inside it) waits for a free one, so
// keep such nesting off hot paths.
func pooledQueries(sqlDB *sql.DB) *Queries {
	sqlDB.SetMaxOpenConns(maxOpenConns)
	// Idle connections are kept, not closed: the default of two would reopen a
	// connection, and rerun its pragmas, on most requests under load.
	sqlDB.SetMaxIdleConns(maxOpenConns)
	return New(sqlDB)
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
