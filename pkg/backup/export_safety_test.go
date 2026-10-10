package backup

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
)

// assertNoTemps fails when an export left a temp file in dir.
func assertNoTemps(t *testing.T, dir string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), storageutil.WriteTempPrefix) {
			t.Errorf("export left %s behind", entry.Name())
		}
	}
}

// A failed export must leave the previous vault backup whole (#3084, F12):
// the file used to be removed and rebuilt in place.
func TestExportVault_FailureKeepsPreviousBackup(t *testing.T) {
	d, queries, liveKey := setupLiveVaultDB(t, "master-password-123")
	defer vaultcrypto.ZeroKey(liveKey)
	addTestEntry(t, d, liveKey, "GitHub", "alice", "gh-secret")

	targetDir := t.TempDir()
	dbPath, err := ExportVault(context.Background(), queries, liveKey, "recovery-password-456", targetDir)
	if err != nil {
		t.Fatalf("first export: %v", err)
	}
	before, err := BackupVaultChecksum(dbPath)
	if err != nil {
		t.Fatal(err)
	}

	// An entry the live key cannot open fails the export partway through.
	if _, err := d.Exec(
		`INSERT INTO vault_entries (name, url_host, ciphertext, nonce) VALUES ('broken', 'example.com', x'00', x'00')`,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := ExportVault(context.Background(), queries, liveKey, "recovery-password-456", targetDir); err == nil {
		t.Fatal("export of an entry the key cannot open succeeded")
	}

	after, err := BackupVaultChecksum(dbPath)
	if err != nil {
		t.Fatalf("the previous backup is gone: %v", err)
	}
	if after != before {
		t.Error("a failed export changed the previous backup")
	}
	assertNoTemps(t, targetDir)
}

// Two exports onto one target must not write through each other (#3084, F12).
func TestExportVault_ConcurrentExportsBothSucceed(t *testing.T) {
	d, queries, liveKey := setupLiveVaultDB(t, "master-password-123")
	defer vaultcrypto.ZeroKey(liveKey)
	for _, name := range []string{"a", "b", "c", "d"} {
		addTestEntry(t, d, liveKey, name, "alice", "secret")
	}
	targetDir := t.TempDir()

	errs := make([]error, 4)
	var wg sync.WaitGroup
	for i := range errs {
		wg.Go(func() {
			_, errs[i] = ExportVault(context.Background(), queries, liveKey, "recovery-password-456", targetDir)
		})
	}
	wg.Wait()
	for _, err := range errs {
		if err != nil {
			t.Errorf("concurrent export: %v", err)
		}
	}

	// Whichever export won the rename, the file is one whole export.
	backupDB, err := sql.Open("sqlite", db.DSN(filepath.Join(targetDir, backupVaultFilename)))
	if err != nil {
		t.Fatal(err)
	}
	defer backupDB.Close()
	var entries int
	if err := backupDB.QueryRow(`SELECT COUNT(*) FROM vault_entries`).Scan(&entries); err != nil {
		t.Fatalf("the backup two exports raced for does not read: %v", err)
	}
	if entries != 4 {
		t.Errorf("backup holds %d entries, want 4", entries)
	}
	assertNoTemps(t, targetDir)
}

// Two chat exports used to share one temp name and remove each other's
// (#3084, F13).
func TestExportChat_ConcurrentExportsBothSucceed(t *testing.T) {
	database := dbtest.NewDB(t)
	seedChat(t, database.Db)
	targetDir := t.TempDir()

	errs := make([]error, 4)
	var wg sync.WaitGroup
	for i := range errs {
		wg.Go(func() {
			_, errs[i] = ExportChat(context.Background(), database.Db, targetDir)
		})
	}
	wg.Wait()
	for _, err := range errs {
		if err != nil {
			t.Errorf("concurrent export: %v", err)
		}
	}

	live := dbtest.NewDB(t).Db
	addChatUsers(t, live, "alice", "bob", "carol")
	result, err := ImportChat(context.Background(), live, targetDir)
	if err != nil {
		t.Fatalf("the backup two exports raced for does not import: %v", err)
	}
	if result.Messages != 4 {
		t.Errorf("restored %d messages, want 4", result.Messages)
	}
	assertNoTemps(t, targetDir)
}
