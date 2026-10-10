package backup

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	// Registers the "sqlite" driver with database/sql.
	_ "modernc.org/sqlite"
)

const backupVaultFilename = "vault_backup.db"

// stagedVaultMaxAge is how old a staged vault export has to be before a new
// backup removes it as left over from a run that crashed. A younger one may
// belong to a request on another instance that has not queued its job yet.
const stagedVaultMaxAge = time.Hour

// ExportVault writes the vault, re-encrypted under recoveryPassword, to
// vault_backup.db in targetDir and returns its path. The file is built under a
// temp name of its own and renamed into place, so a failed export leaves the
// previous backup whole and two exports never write one file (#3084).
func ExportVault(ctx context.Context, queries *db.Queries, liveKey []byte, recoveryPassword string, targetDir string) (string, error) {
	staged, err := stageVaultExport(ctx, queries, liveKey, recoveryPassword, targetDir)
	if err != nil {
		return "", err
	}
	defer removeStagedVault(targetDir, staged)
	if err := commitStagedVault(targetDir, staged); err != nil {
		return "", err
	}
	return filepath.Join(targetDir, backupVaultFilename), nil
}

// stageVaultExport builds the vault export in targetDir under a temp name no
// other export shares, and returns that name. [commitStagedVault] puts it in
// place; nothing is left behind when it fails.
func stageVaultExport(ctx context.Context, queries *db.Queries, liveKey []byte, recoveryPassword string, targetDir string) (string, error) {
	name := storageutil.WriteTempPrefix + rand.Text() + "-" + backupVaultFilename
	tmpPath := filepath.Join(targetDir, name)
	if err := buildVaultBackup(ctx, queries, liveKey, recoveryPassword, tmpPath); err != nil {
		removeStagedVault(targetDir, name)
		return "", err
	}
	if err := storageutil.SyncFile(tmpPath); err != nil {
		removeStagedVault(targetDir, name)
		return "", fmt.Errorf("flush vault backup: %w", err)
	}
	return name, nil
}

// commitStagedVault renames the export [stageVaultExport] built to
// vault_backup.db, replacing the previous backup whole. name comes out of a
// job's params, so anything that is not a staged export's name is refused.
func commitStagedVault(targetDir, name string) error {
	if !isStagedVaultName(name) {
		return fmt.Errorf("%q is not a staged vault export", name)
	}
	if err := os.Rename(filepath.Join(targetDir, name), filepath.Join(targetDir, backupVaultFilename)); err != nil {
		if os.IsNotExist(err) {
			return errors.New("the staged vault export is gone; start a new backup")
		}
		return fmt.Errorf("replace vault backup: %w", err)
	}
	if err := storageutil.SyncDir(targetDir); err != nil {
		return fmt.Errorf("flush vault backup directory: %w", err)
	}
	return nil
}

// removeStagedVault removes a staged export and the rollback journal a crash
// may have left beside it. It does nothing once the export has been committed.
func removeStagedVault(targetDir, name string) {
	if !isStagedVaultName(name) {
		return
	}
	os.Remove(filepath.Join(targetDir, name))
	os.Remove(filepath.Join(targetDir, name+"-journal"))
}

// removeStaleStagedVaults removes the staged exports in targetDir that are
// older than [stagedVaultMaxAge].
func removeStaleStagedVaults(targetDir string) {
	entries, err := os.ReadDir(targetDir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		name := strings.TrimSuffix(entry.Name(), "-journal")
		if !isStagedVaultName(name) {
			continue
		}
		if info, err := entry.Info(); err == nil && time.Since(info.ModTime()) > stagedVaultMaxAge {
			os.Remove(filepath.Join(targetDir, entry.Name()))
		}
	}
}

func isStagedVaultName(name string) bool {
	return name == filepath.Base(name) &&
		strings.HasPrefix(name, storageutil.WriteTempPrefix) &&
		strings.HasSuffix(name, "-"+backupVaultFilename)
}

// buildVaultBackup writes the export as a new SQLite file at dbPath.
func buildVaultBackup(ctx context.Context, queries *db.Queries, liveKey []byte, recoveryPassword string, dbPath string) error {
	config, err := queries.GetVaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("get vault config: %w", err)
	}

	if !vaultcrypto.CheckVerificationBlob(liveKey, config.VerificationBlob, config.VerificationNonce) {
		return errors.New("live vault key verification failed")
	}

	newSalt, err := vaultcrypto.GenerateSalt()
	if err != nil {
		return fmt.Errorf("generate recovery salt: %w", err)
	}

	recoveryParams := vaultcrypto.DefaultParams()
	recoveryKey := vaultcrypto.DeriveKey(recoveryPassword, newSalt, recoveryParams)
	defer vaultcrypto.ZeroKey(recoveryKey)

	verBlob, verNonce, err := vaultcrypto.MakeVerificationBlob(recoveryKey)
	if err != nil {
		return fmt.Errorf("make recovery verification blob: %w", err)
	}

	// Through db.DSN like every other database this codebase opens: the rows
	// below carry created_at and updated_at straight across, and a connection
	// without _time_format=datetime&_timezone=UTC would write them in Go's
	// t.String() form, which no SQLite date function can parse (#1650).
	backupDB, err := sql.Open("sqlite", db.DSN(dbPath))
	if err != nil {
		return fmt.Errorf("open backup vault db: %w", err)
	}
	defer backupDB.Close()

	if err := createBackupVaultSchema(backupDB); err != nil {
		return fmt.Errorf("create backup schema: %w", err)
	}

	_, err = backupDB.ExecContext(ctx,
		`INSERT INTO vault_config (id, salt, argon2_memory, argon2_iterations, argon2_parallelism,
			verification_blob, verification_nonce, auto_lock_seconds)
		VALUES (1, ?, ?, ?, ?, ?, ?, ?)`,
		newSalt, recoveryParams.Memory, recoveryParams.Iterations, recoveryParams.Parallelism,
		verBlob, verNonce, config.AutoLockSeconds,
	)
	if err != nil {
		return fmt.Errorf("insert backup vault config: %w", err)
	}

	folders, err := queries.ListVaultFolders(ctx)
	if err != nil {
		return fmt.Errorf("list vault folders: %w", err)
	}
	if err := copyFolders(ctx, backupDB, folders); err != nil {
		return err
	}

	entries, err := queries.ListAllVaultEntriesForReEncrypt(ctx)
	if err != nil {
		return fmt.Errorf("list vault entries: %w", err)
	}

	fullEntries := make([]db.VaultEntry, 0, len(entries))
	for _, e := range entries {
		full, err := queries.GetVaultEntry(ctx, e.ID)
		if err != nil {
			return fmt.Errorf("get full entry %d: %w", e.ID, err)
		}
		fullEntries = append(fullEntries, full)
	}

	for _, entry := range fullEntries {
		plaintext, err := vaultcrypto.Decrypt(liveKey, entry.Ciphertext, entry.Nonce)
		if err != nil {
			return fmt.Errorf("decrypt entry %d: %w", entry.ID, err)
		}

		newCiphertext, newNonce, err := vaultcrypto.Encrypt(recoveryKey, plaintext)
		if err != nil {
			return fmt.Errorf("re-encrypt entry %d: %w", entry.ID, err)
		}

		_, err = backupDB.ExecContext(ctx,
			`INSERT INTO vault_entries (id, name, url_host, folder_id, ciphertext, nonce, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			entry.ID, entry.Name, entry.UrlHost, entry.FolderID,
			newCiphertext, newNonce, entry.CreatedAt, entry.UpdatedAt,
		)
		if err != nil {
			return fmt.Errorf("insert backup entry %d: %w", entry.ID, err)
		}
	}

	return nil
}

// BackupVaultChecksum returns the hex-encoded SHA-256 of the backup vault DB file.
func BackupVaultChecksum(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	// Streamed rather than read whole: the vault DB grows with entry count and
	// hashing never needed it in memory (#1723).
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func createBackupVaultSchema(d *sql.DB) error {
	return db.InitVaultSchema(d)
}

// copyFolders writes the folder tree into the backup database with its ids
// preserved, so entries can point at the same folder they pointed at live.
//
// ListVaultFolders orders by sort_order then name, which says nothing about
// depth: a child sorted before its parent arrives before the row its parent_id
// names. Rather than topologically sort a tree that only has to survive until
// COMMIT, the whole copy runs in one transaction with foreign key checks
// deferred to the end of it — every parent is present by then, and a genuinely
// dangling parent_id still fails, at COMMIT instead of at the INSERT.
func copyFolders(ctx context.Context, backupDB *sql.DB, folders []db.VaultFolder) error {
	tx, err := backupDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin backup folder copy: %w", err)
	}
	defer tx.Rollback()

	// Per-connection and per-transaction: SQLite clears it at COMMIT, and
	// issuing it through the transaction pins it to the connection the inserts
	// below actually run on.
	if _, err := tx.ExecContext(ctx, `PRAGMA defer_foreign_keys = ON`); err != nil {
		return fmt.Errorf("defer foreign keys: %w", err)
	}

	for _, f := range folders {
		_, err := tx.ExecContext(ctx,
			`INSERT INTO vault_folders (id, name, parent_id, sort_order, created_at)
			VALUES (?, ?, ?, ?, ?)`,
			f.ID, f.Name, f.ParentID, f.SortOrder, f.CreatedAt,
		)
		if err != nil {
			return fmt.Errorf("insert backup folder %d: %w", f.ID, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit backup folder copy: %w", err)
	}
	return nil
}
