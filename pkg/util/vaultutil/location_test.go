package vaultutil

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
)

// openTestMainDB stands in for the main database: the vault tables, which
// moving the vault back to internal storage writes, plus the vault_location
// row that records where the vault lives.
func openTestMainDB(t *testing.T, serial string) *db.DatabaseSqlc {
	t.Helper()
	main := openTestVault(t)
	if _, err := main.Db.Exec(`CREATE TABLE vault_location (
		id INTEGER PRIMARY KEY CHECK (id = 1),
		device_serial TEXT NOT NULL DEFAULT '',
		updated_at DATETIME NOT NULL DEFAULT (datetime('now')))`); err != nil {
		t.Fatal(err)
	}
	if _, err := main.Db.Exec(`INSERT INTO vault_location (id, device_serial) VALUES (1, ?)`, serial); err != nil {
		t.Fatal(err)
	}
	return main
}

func seedTestVault(t *testing.T, vault *db.DatabaseSqlc, entries int) {
	t.Helper()
	ctx := context.Background()
	if err := vault.Queries.CreateVaultConfig(ctx, db.CreateVaultConfigParams{
		Salt: []byte("salt"), Argon2Memory: 1, Argon2Iterations: 1, Argon2Parallelism: 1,
		VerificationBlob: []byte("blob"), VerificationNonce: []byte("nonce"), AutoLockSeconds: 300,
	}); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < entries; i++ {
		if _, err := CreateEntry(ctx, CreateEntryParams{
			Queries: vault.Queries, Key: testKey, Fields: EntryFields{Name: "entry", Password: "pw"},
		}); err != nil {
			t.Fatal(err)
		}
	}
}

func vaultEntryCount(t *testing.T, vault *db.DatabaseSqlc) int {
	t.Helper()
	var n int
	if err := vault.Db.QueryRow(`SELECT count(*) FROM vault_entries`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// The recorded location must name a whole vault at every step of a move. A
// source that cannot be emptied stands in for a crash right after the copy:
// emptying the source before recording the new location left the location
// pointing at a vault with no entries in it (#2517).
func TestSetLocation_RecordedLocationNeverNamesAnEmptiedVault(t *testing.T) {
	ctx := context.Background()
	main := openTestMainDB(t, "EXT1")

	external, err := sql.Open("sqlite", db.DSN(filepath.Join(t.TempDir(), "vault.db")))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { external.Close() })
	if err := db.InitVaultSchema(external); err != nil {
		t.Fatal(err)
	}
	source := &db.DatabaseSqlc{Db: external, Queries: db.New(external)}
	seedTestVault(t, source, 3)
	if _, err := external.Exec(`CREATE TRIGGER power_cut BEFORE DELETE ON vault_config
		BEGIN SELECT RAISE(ABORT, 'power cut'); END`); err != nil {
		t.Fatal(err)
	}

	_, moveErr := SetLocation(ctx, SetLocationParams{MainDB: main, VaultDB: source})

	serial, err := main.Queries.GetVaultLocation(ctx)
	if err != nil {
		t.Fatal(err)
	}
	recorded := source
	if serial == "" {
		recorded = main
	}
	if _, err := recorded.Queries.GetVaultConfig(ctx); err != nil {
		t.Fatalf("vault at recorded location %q has no config: %v", serial, err)
	}
	if n := vaultEntryCount(t, recorded); n != 3 {
		t.Fatalf("vault at recorded location %q has %d entries, want 3", serial, n)
	}
	if moveErr != nil {
		t.Fatalf("SetLocation: %v", moveErr)
	}
}
