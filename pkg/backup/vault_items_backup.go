package backup

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strconv"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
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
	// ErrVaultKeyExists reports a backup vault whose account here already has
	// a vault key (quark-project#267). A restore never replaces a key: a
	// session open on the account would go on sealing items under the old
	// one, and they would be lost. Its error names every such account.
	ErrVaultKeyExists = errors.New("an account the backup has a vault for already has a vault on this Quark, " +
		"and a restore never replaces one; that account can delete its empty vault, then restore again")
	// ErrVaultBackupInvalid reports a backup vault key or item that this
	// Quark would refuse if a client sent it (vaultutil.ValidateKey and
	// ValidateItem, #3648). Its error names every such account.
	ErrVaultBackupInvalid = errors.New("the backup holds a vault key or item this Quark does not accept")
	// ErrVaultRestoreRoleRequired reports a drive that does not have the
	// snapshot-backup role. A vault is only restored from the drive the
	// snapshots write to.
	ErrVaultRestoreRoleRequired = errors.New("a vault is restored only from a drive with the snapshot-backup role")
)

// maxRestoredCiphertextBytes bounds a restored item's ciphertext. No API write
// can store a longer one: the item's body is at most
// vaultutil.MaxItemRequestBytes, and the ciphertext travels in it as base64.
const maxRestoredCiphertextBytes = vaultutil.MaxItemRequestBytes

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
	check:       checkVaultRestore,
	steps:       vaultRestoreSteps,
	settle:      settleVaultRestore,
}

// vaultRestoreSteps is the vault's restore, keys before the items under them.
// Raw SQL for the reason [chatRestoreSteps] gives. u is the backup account's
// row in temp.restore_users; the inner JOIN skips an account that is not on
// this Quark, as vault_keys' and vault_items' ON DELETE CASCADE would have.
var vaultRestoreSteps = []restoreStep{
	// Never OR REPLACE: [checkVaultRestore] has refused a restore onto an
	// account that has a key, so a collision here is a fault, not a key to
	// overwrite. An account the backup does not know keeps its key.
	{"vault_keys", `
		INSERT INTO main.vault_keys (user_id, wrapped_by_password, salt_pw,
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

// checkVaultRestore refuses, before any row is written, a restore that would
// replace a vault key on this Quark or store a key or item no API write could
// (quark-project#267). Both name the accounts.
func checkVaultRestore(ctx context.Context, conn *sql.Conn) error {
	keyed, err := queryStrings(ctx, conn, `
		SELECT u.username FROM vault_items_backup.vault_keys AS b
		JOIN temp.restore_users AS r ON r.backup_id = b.user_id
		JOIN main.vault_keys AS k ON k.user_id = r.live_id
		JOIN main.users AS u ON u.id = r.live_id
		ORDER BY u.username`)
	if err != nil {
		return fmt.Errorf("list accounts that have a vault key: %w", err)
	}
	if len(keyed) > 0 {
		return fmt.Errorf("%w (%s)", ErrVaultKeyExists, strings.Join(keyed, ", "))
	}

	invalid, err := invalidVaultAccounts(ctx, conn)
	if err != nil {
		return err
	}
	if len(invalid) > 0 {
		return fmt.Errorf("%w (%s)", ErrVaultBackupInvalid, strings.Join(invalid, ", "))
	}
	return nil
}

// invalidVaultAccounts runs vaultutil.ValidateKey and ValidateItem over every
// key and item in the backup and returns, sorted, the backup usernames whose
// rows fail. An item's ciphertext is length-checked in SQL first, so no row
// longer than an API write could store is ever read onto the heap.
func invalidVaultAccounts(ctx context.Context, conn *sql.Conn) ([]string, error) {
	invalid := map[string]bool{}

	keys, err := conn.QueryContext(ctx, `
		SELECT u.username, k.wrapped_by_password, k.salt_pw, k.wrapped_by_phrase, k.salt_rp, k.kdf_params
		FROM vault_items_backup.vault_keys AS k
		JOIN vault_items_backup.users AS u ON u.id = k.user_id`)
	if err != nil {
		return nil, fmt.Errorf("read backup vault keys: %w", err)
	}
	for keys.Next() {
		var username, kdfParams string
		var key vaultutil.Key
		if err := keys.Scan(&username, &key.WrappedByPassword, &key.SaltPw, &key.WrappedByPhrase, &key.SaltRp, &kdfParams); err != nil {
			keys.Close()
			return nil, fmt.Errorf("scan backup vault key: %w", err)
		}
		key.KdfParams = json.RawMessage(kdfParams)
		if vaultutil.ValidateKey(key) != nil {
			invalid[username] = true
		}
	}
	keys.Close()
	if err := keys.Err(); err != nil {
		return nil, fmt.Errorf("read backup vault keys: %w", err)
	}

	oversized, err := queryStrings(ctx, conn, `
		SELECT DISTINCT u.username FROM vault_items_backup.vault_items AS i
		JOIN vault_items_backup.users AS u ON u.id = i.user_id
		WHERE length(i.ciphertext) > `+strconv.Itoa(maxRestoredCiphertextBytes))
	if err != nil {
		return nil, fmt.Errorf("check backup vault item sizes: %w", err)
	}
	for _, username := range oversized {
		invalid[username] = true
	}

	items, err := conn.QueryContext(ctx, `
		SELECT u.username, i.ciphertext, i.nonce, i.format_version
		FROM vault_items_backup.vault_items AS i
		JOIN vault_items_backup.users AS u ON u.id = i.user_id
		WHERE length(i.ciphertext) <= `+strconv.Itoa(maxRestoredCiphertextBytes))
	if err != nil {
		return nil, fmt.Errorf("read backup vault items: %w", err)
	}
	defer items.Close()
	for items.Next() {
		var username string
		var fields vaultutil.ItemFields
		if err := items.Scan(&username, &fields.Ciphertext, &fields.Nonce, &fields.FormatVersion); err != nil {
			return nil, fmt.Errorf("scan backup vault item: %w", err)
		}
		if vaultutil.ValidateItem(fields) != nil {
			invalid[username] = true
		}
	}
	if err := items.Err(); err != nil {
		return nil, fmt.Errorf("read backup vault items: %w", err)
	}

	names := slices.Sorted(maps.Keys(invalid))
	return names, nil
}

// settleVaultRestore refuses a restore that would leave a backup vault behind,
// and names the restored accounts whose vault opens only with the password
// they had when the backup was taken, and lists every account it restored, so
// the caller can tell each one's sessions. A handful of rows, one per account.
//
// The right account for a vault is the one on this Quark whose username is
// the backup's byte for byte, the lookup sign-in makes: never "Carol" for
// "carol". A vault with no such account is refused rather than dropped,
// because once any vault has items a second restore is refused too, and the
// skipped vault could never come back.
func settleVaultRestore(ctx context.Context, conn *sql.Conn) (restoreReport, error) {
	missing, err := queryStrings(ctx, conn, `
		SELECT b.username FROM vault_items_backup.users AS b
		JOIN vault_items_backup.vault_keys AS k ON k.user_id = b.id
		WHERE b.id NOT IN (SELECT backup_id FROM temp.restore_users)
		ORDER BY b.username`)
	if err != nil {
		return restoreReport{}, fmt.Errorf("list vaults with no account: %w", err)
	}
	if len(missing) > 0 {
		return restoreReport{}, fmt.Errorf("%w (%s)", ErrVaultAccountMissing, strings.Join(missing, ", "))
	}

	restored, err := restoredVaultAccounts(ctx, conn)
	if err != nil {
		return restoreReport{}, err
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
		return restoreReport{}, fmt.Errorf("compare restored vault salts: %w", err)
	}
	defer rows.Close()
	var backupPassword []string
	for rows.Next() {
		var username, authSalt string
		var saltPw []byte
		if err := rows.Scan(&username, &authSalt, &saltPw); err != nil {
			return restoreReport{}, fmt.Errorf("scan restored vault salt: %w", err)
		}
		if base64.StdEncoding.EncodeToString(saltPw) != authSalt {
			backupPassword = append(backupPassword, username)
		}
	}
	return restoreReport{named: backupPassword, restored: restored}, rows.Err()
}

// restoredVaultAccounts is the live accounts, by username, that the restore
// gave a vault key or item.
func restoredVaultAccounts(ctx context.Context, conn *sql.Conn) ([]restoredAccount, error) {
	rows, err := conn.QueryContext(ctx, `
		SELECT u.id, u.username FROM temp.restore_users AS r
		JOIN main.users AS u ON u.id = r.live_id
		WHERE r.backup_id IN (SELECT user_id FROM vault_items_backup.vault_keys
			UNION SELECT user_id FROM vault_items_backup.vault_items)
		ORDER BY u.username`)
	if err != nil {
		return nil, fmt.Errorf("list restored vault accounts: %w", err)
	}
	defer rows.Close()
	var restored []restoredAccount
	for rows.Next() {
		var account restoredAccount
		if err := rows.Scan(&account.userID, &account.username); err != nil {
			return nil, fmt.Errorf("scan restored vault account: %w", err)
		}
		restored = append(restored, account)
	}
	return restored, rows.Err()
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
	return vaultBackup.export(ctx, liveDB, targetDir, nil)
}

// ImportVault restores the vault_items_backup.db that [ExportVault] wrote to
// backupDir into liveDB, in one transaction: a refused or failed restore
// changes nothing. It is the vault's half of the restore [ImportChat] is the
// chat's half of (#2428); [RestoreVault] is its route's way in.
//
// It restores only while no account has a vault item, and answers
// [ErrVaultNotEmpty] otherwise. It never replaces a vault key: a backup vault
// whose account here already has one refuses the restore with
// [ErrVaultKeyExists]. Every backup key and item must pass the checks an API
// write does, or the restore is refused with [ErrVaultBackupInvalid]. Each account's key and items come back under
// the account of the same username on this Quark, byte for byte, and a vault
// with no such account refuses the restore with [ErrVaultAccountMissing]. An
// account in the backup with no vault and no account here is only named.
//
// The wrapped key carries the salt it was derived over, so a vault restored
// onto new hardware opens with the password its account had at backup time;
// the result's BackupPasswordAccounts names those accounts (#3614).
func ImportVault(ctx context.Context, liveDB *sql.DB, backupDir string) (VaultImportResult, error) {
	rows, unmatched, report, err := vaultBackup.restore(ctx, liveDB, backupDir)
	if err != nil {
		return VaultImportResult{}, err
	}
	result := VaultImportResult{
		Accounts:               int(rows["vault_keys"]),
		Items:                  int(rows["vault_items"]),
		UnmatchedUsers:         unmatched,
		BackupPasswordAccounts: report.named,
		RestoredAccounts:       make([]string, 0, len(report.restored)),
		RestoredUserIDs:        make([]int64, 0, len(report.restored)),
	}
	for _, account := range report.restored {
		result.RestoredAccounts = append(result.RestoredAccounts, account.username)
		result.RestoredUserIDs = append(result.RestoredUserIDs, account.userID)
	}
	return result, nil
}

// RestoreVault restores, as [ImportVault] does, the vault backup a snapshot
// wrote to the drive params.DeviceSerial names. A drive that is not attached
// is a *fileutil.NotFoundError, and one without the snapshot-backup role is
// [ErrVaultRestoreRoleRequired]: a restore reads only the drive snapshots are
// written to, never whatever drive holds a file of the right name. A file
// this Quark did not write, or one changed since, is
// [ErrBackupNotFromThisQuark] and nothing is restored (#4010).
func RestoreVault(params RestoreVaultParams) (VaultImportResult, error) {
	drive, err := fileutil.FilesVFS(params.Registry, params.DeviceSerial)
	if err != nil {
		return VaultImportResult{}, err
	}
	role, err := params.Queries.GetDeviceRole(params.Ctx, params.DeviceSerial)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && role != "snapshot-backup") {
		return VaultImportResult{}, ErrVaultRestoreRoleRequired
	}
	if err != nil {
		return VaultImportResult{}, fmt.Errorf("read the drive's role: %w", err)
	}
	dir, err := hostDir(params.Ctx, drive)
	if err != nil {
		return VaultImportResult{}, err
	}
	if err := vaultBackup.checkBinding(params.Ctx, params.Queries, params.DeviceSerial, dir); err != nil {
		return VaultImportResult{}, err
	}
	return ImportVault(params.Ctx, params.LiveDB, dir)
}
