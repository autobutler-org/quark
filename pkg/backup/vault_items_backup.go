package backup

import (
	"context"
	"database/sql"
	"errors"

	"github.com/autobutler-org/quark/internal/db"
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
// chat's half of (#2428), and like it has no route of its own yet.
//
// It restores only while no account has a vault item, and answers
// [ErrVaultNotEmpty] otherwise. Each account's key and items come back under
// the account of the same username on this Quark, byte for byte; an account
// that is not here is skipped and named in the result.
func ImportVault(ctx context.Context, liveDB *sql.DB, backupDir string) (VaultImportResult, error) {
	rows, unmatched, err := vaultBackup.restore(ctx, liveDB, backupDir)
	if err != nil {
		return VaultImportResult{}, err
	}
	return VaultImportResult{
		Accounts:       int(rows["vault_keys"]),
		Items:          int(rows["vault_items"]),
		UnmatchedUsers: unmatched,
	}, nil
}
