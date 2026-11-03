package backup

import (
	"context"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
)

// backupVaultFilename is the per-account vault's backup file. Not
// vault_backup.db: older snapshots hold the household vault, re-encrypted
// under a recovery password, under that name, and a restore must never take
// one for the other.
const backupVaultFilename = "vault_items_backup.db"

// The reasons [ImportVault] turns a restore down that the caller can explain
// to whoever asked for it. Anything else it returns is a fault.
var (
	// ErrVaultNotEmpty reports a live Quark where some account already keeps
	// a vault item. A restore replaces the vaults; it never merges.
	ErrVaultNotEmpty = errors.New("a vault already has items")
	// ErrVaultBackupVersion reports a backup file in a format this build does
	// not read.
	ErrVaultBackupVersion = errors.New("vault backup was written by a different version of Quark")
	// ErrVaultAccountMissing reports a backup vault whose username has no
	// account on this Quark (#3614). Its error names every such username, so
	// an admin can add the accounts and restore again.
	ErrVaultAccountMissing = errors.New("the backup has a vault for an account this Quark does not have; " +
		"add an account with the same username, letter for letter, and restore again")
)

// vaultBackup is the per-account vault's ciphertext backup,
// vault_items_backup.db.
var vaultBackup = ciphertextBackup{
	filename:   backupVaultFilename,
	feature:    "Vault backup",
	ddl:        db.VaultItemsBackupSchemaDDL,
	version:    db.VaultItemsBackupVersion,
	errVersion: ErrVaultBackupVersion,
	directory: []string{
		`INSERT INTO vault_items_backup.users (id, username) SELECT id, username FROM main.users`,
	},
	tables:      []string{"vault_keys", "vault_items"},
	occupied:    `SELECT EXISTS (SELECT 1 FROM main.vault_items)`,
	errOccupied: ErrVaultNotEmpty,
	steps:       vaultRestoreSteps,
	settle:      settleVaultRestore,
}

// vaultRestoreSteps is the vault's restore, keys before the items under them.
// Raw SQL for the reason [chatRestoreSteps] gives. u is the backup account's
// row in temp.restore_users; the inner JOIN skips an account that is not on
// this Quark, as vault_keys' and vault_items' ON DELETE CASCADE would have.
var vaultRestoreSteps = []restoreStep{
	// OR REPLACE: an account that signed in to the new install may already
	// have made itself a vault key, and every item in the backup is sealed
	// under the old one. An account the backup does not know keeps its key.
	{"vault_keys", `
		INSERT OR REPLACE INTO main.vault_keys (user_id, wrapped_by_password, salt_pw,
			wrapped_by_phrase, salt_rp, kdf_params, created_at, updated_at)
		SELECT u.live_id, k.wrapped_by_password, k.salt_pw,
			k.wrapped_by_phrase, k.salt_rp, k.kdf_params, k.created_at, k.updated_at
		FROM vault_items_backup.vault_keys AS k
		JOIN temp.restore_users AS u ON u.backup_id = k.user_id`},
	// Item ids are kept, as the chat's message ids are: the live table is
	// empty, so none can collide.
	{"vault_items", `
		INSERT INTO main.vault_items (id, user_id, ciphertext, nonce, format_version, created_at, updated_at)
		SELECT i.id, u.live_id, i.ciphertext, i.nonce, i.format_version, i.created_at, i.updated_at
		FROM vault_items_backup.vault_items AS i
		JOIN temp.restore_users AS u ON u.backup_id = i.user_id`},
}

// settleVaultRestore refuses a restore that would leave a backup vault behind,
// and names the restored accounts whose vault opens only with the password
// they had when the backup was taken. A handful of rows, one per account.
//
// The right account for a vault is the one on this Quark whose username is
// the backup's byte for byte, the lookup sign-in makes: never "Carol" for
// "carol". A vault with no such account is refused rather than dropped,
// because once any vault has items a second restore is refused too, and the
// skipped vault could never come back.
func settleVaultRestore(ctx context.Context, conn *sql.Conn) ([]string, error) {
	missing, err := queryStrings(ctx, conn, `
		SELECT b.username FROM vault_items_backup.users AS b
		JOIN vault_items_backup.vault_keys AS k ON k.user_id = b.id
		WHERE b.id NOT IN (SELECT backup_id FROM temp.restore_users)
		ORDER BY b.username`)
	if err != nil {
		return nil, fmt.Errorf("list vaults with no account: %w", err)
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("%w (%s)", ErrVaultAccountMissing, strings.Join(missing, ", "))
	}

	// salt_pw is what the wrap was derived over and auth_salt is the base64
	// salt this Quark derives the account's keys over. SQLite has no base64,
	// so they are compared here.
	rows, err := conn.QueryContext(ctx, `
		SELECT u.username, u.auth_salt, k.salt_pw
		FROM vault_items_backup.vault_keys AS b
		JOIN temp.restore_users AS r ON r.backup_id = b.user_id
		JOIN main.vault_keys AS k ON k.user_id = r.live_id
		JOIN main.users AS u ON u.id = r.live_id
		ORDER BY u.username`)
	if err != nil {
		return nil, fmt.Errorf("compare restored vault salts: %w", err)
	}
	defer rows.Close()
	var backupPassword []string
	for rows.Next() {
		var username, authSalt string
		var saltPw []byte
		if err := rows.Scan(&username, &authSalt, &saltPw); err != nil {
			return nil, fmt.Errorf("scan restored vault salt: %w", err)
		}
		if base64.StdEncoding.EncodeToString(saltPw) != authSalt {
			backupPassword = append(backupPassword, username)
		}
	}
	return backupPassword, rows.Err()
}

// ExportVault writes every account's vault key and items in liveDB to
// vault_items_backup.db in targetDir and returns its path (#3460). Like
// [ExportChat] it asks for no password: the items are ciphertext under each
// account's vault key, and the key is stored only wrapped under the account's
// password or recovery phrase, so the copy is as private as the database it
// came from and a restored vault opens with what opened it before.
//
// A failed export leaves the previous backup whole, and a PostgreSQL-backed
// Quark gets [ErrDatabaseBackedUpSeparately] and nothing written.
func ExportVault(ctx context.Context, liveDB *sql.DB, targetDir string) (string, error) {
	return vaultBackup.export(ctx, liveDB, targetDir)
}

// ImportVault restores the vault_items_backup.db that [ExportVault] wrote to
// backupDir into liveDB, in one transaction: a refused or failed restore
// changes nothing. It is the vault's half of the restore [ImportChat] is the
// chat's half of (#2428); [RestoreVault] is its route's way in.
//
// It restores only while no account has a vault item, and answers
// [ErrVaultNotEmpty] otherwise. Each account's key and items come back under
// the account of the same username on this Quark, byte for byte, and a vault
// with no such account refuses the restore with [ErrVaultAccountMissing]. An
// account in the backup with no vault and no account here is only named.
//
// The wrapped key carries the salt it was derived over, so a vault restored
// onto new hardware opens with the password its account had at backup time;
// the result's BackupPasswordAccounts names those accounts (#3614).
func ImportVault(ctx context.Context, liveDB *sql.DB, backupDir string) (VaultImportResult, error) {
	rows, unmatched, backupPassword, err := vaultBackup.restore(ctx, liveDB, backupDir)
	if err != nil {
		return VaultImportResult{}, err
	}
	return VaultImportResult{
		Accounts:               int(rows["vault_keys"]),
		Items:                  int(rows["vault_items"]),
		UnmatchedUsers:         unmatched,
		BackupPasswordAccounts: backupPassword,
	}, nil
}

// RestoreVault restores, as [ImportVault] does, the vault backup a snapshot
// wrote to the drive params.DeviceSerial names. A drive that is not attached
// is a *fileutil.NotFoundError.
func RestoreVault(params RestoreVaultParams) (VaultImportResult, error) {
	drive, err := fileutil.FilesVFS(params.Registry, params.DeviceSerial)
	if err != nil {
		return VaultImportResult{}, err
	}
	dir, err := hostDir(params.Ctx, drive)
	if err != nil {
		return VaultImportResult{}, err
	}
	return ImportVault(params.Ctx, params.LiveDB, dir)
}
