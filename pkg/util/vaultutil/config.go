package vaultutil

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
)

// defaultAutoLockSeconds is how long a freshly set-up vault stays unlocked.
const defaultAutoLockSeconds = 300

// SetupParams initializes a vault with its first master password.
type SetupParams struct {
	Queries *db.Queries
	// Session is unlocked on success, so setup leaves the vault usable.
	Session        *vaultcrypto.VaultSession
	MasterPassword string
}

// SetupResult reports the state setup left the vault in.
type SetupResult struct {
	Initialized bool
	Locked      bool
}

// UnlockParams derives the vault key from a master password and holds it in
// the session until the auto-lock timeout.
type UnlockParams struct {
	Queries        *db.Queries
	Session        *vaultcrypto.VaultSession
	MasterPassword string
}

// UnlockResult reports the state the unlock left the vault in.
type UnlockResult struct {
	Locked bool
}

// ChangePasswordParams rotates the master password, re-encrypting every entry
// under the new key.
type ChangePasswordParams struct {
	// VaultDB is the vault database; the rotation runs in one transaction on
	// it so a partial failure cannot leave some entries on the old key.
	VaultDB *db.DatabaseSqlc
	Session *vaultcrypto.VaultSession
	// OldKey is the currently unlocked vault key, used to read the entries.
	OldKey          []byte
	CurrentPassword string
	NewPassword     string
}

// ChangePasswordResult reports how many entries were rewritten.
type ChangePasswordResult struct {
	Changed     bool
	ReEncrypted int
}

// Setup writes the vault's first configuration — salt, Argon2 parameters and
// verification blob — and unlocks the session so the caller can use the vault
// straight away.
//
// It returns [ErrVaultAlreadyInitialized] for a second attempt and
// [ErrMasterPasswordTooShort] for a password under the minimum length.
func Setup(ctx context.Context, params SetupParams) (SetupResult, error) {
	// Check if vault is already initialized.
	if _, err := params.Queries.GetVaultConfig(ctx); err == nil {
		return SetupResult{}, ErrVaultAlreadyInitialized
	} else if !errors.Is(err, sql.ErrNoRows) {
		return SetupResult{}, fmt.Errorf("check vault config: %w", err)
	}

	if len(params.MasterPassword) < minPasswordLength {
		return SetupResult{}, ErrMasterPasswordTooShort
	}

	salt, err := vaultcrypto.GenerateSalt()
	if err != nil {
		return SetupResult{}, fmt.Errorf("generate salt: %w", err)
	}

	argon2Params := vaultcrypto.DefaultParams()
	key := vaultcrypto.DeriveKey(params.MasterPassword, salt, argon2Params)
	defer vaultcrypto.ZeroKey(key)

	verBlob, verNonce, err := vaultcrypto.MakeVerificationBlob(key)
	if err != nil {
		return SetupResult{}, fmt.Errorf("create verification blob: %w", err)
	}

	if err := params.Queries.CreateVaultConfig(ctx, db.CreateVaultConfigParams{
		Salt:              salt,
		Argon2Memory:      int64(argon2Params.Memory),
		Argon2Iterations:  int64(argon2Params.Iterations),
		Argon2Parallelism: int64(argon2Params.Parallelism),
		VerificationBlob:  verBlob,
		VerificationNonce: verNonce,
		AutoLockSeconds:   defaultAutoLockSeconds,
	}); err != nil {
		return SetupResult{}, fmt.Errorf("save vault config: %w", err)
	}

	// Auto-unlock after setup.
	unlockKey := vaultcrypto.DeriveKey(params.MasterPassword, salt, argon2Params)
	params.Session.Unlock(unlockKey, defaultAutoLockSeconds*time.Second)
	vaultcrypto.ZeroKey(unlockKey)

	return SetupResult{Initialized: true, Locked: false}, nil
}

// Unlock derives the vault key from the master password, checks it against the
// stored verification blob, and hands it to the session.
//
// It returns [ErrVaultNotInitialized] when there is no vault yet and
// [ErrIncorrectMasterPassword] when the password does not match.
func Unlock(ctx context.Context, params UnlockParams) (UnlockResult, error) {
	config, err := params.Queries.GetVaultConfig(ctx)
	if errors.Is(err, sql.ErrNoRows) {
		return UnlockResult{}, ErrVaultNotInitialized
	}
	if err != nil {
		return UnlockResult{}, fmt.Errorf("get vault config: %w", err)
	}

	key := vaultcrypto.DeriveKey(params.MasterPassword, config.Salt, argon2ParamsFrom(config))

	if !vaultcrypto.CheckVerificationBlob(key, config.VerificationBlob, config.VerificationNonce) {
		vaultcrypto.ZeroKey(key)
		return UnlockResult{}, ErrIncorrectMasterPassword
	}

	params.Session.Unlock(key, time.Duration(config.AutoLockSeconds)*time.Second)

	if result, err := BackfillEntryHosts(ctx, BackfillEntryHostsParams{Queries: params.Queries, Key: key}); err != nil {
		slog.Warn("vault: backfill entry hosts", "err", err, "updated", result.Updated)
	}
	vaultcrypto.ZeroKey(key)

	return UnlockResult{Locked: false}, nil
}

// ChangePassword rotates the master password. Every entry is decrypted with
// the old key and re-encrypted with the new one inside a single transaction,
// so a failure part way through leaves the whole vault on the old key rather
// than splitting it across two.
//
// It returns [ErrNewPasswordTooShort] and [ErrIncorrectCurrentPassword].
func ChangePassword(ctx context.Context, params ChangePasswordParams) (ChangePasswordResult, error) {
	if len(params.NewPassword) < minPasswordLength {
		return ChangePasswordResult{}, ErrNewPasswordTooShort
	}

	config, err := params.VaultDB.Queries.GetVaultConfig(ctx)
	if err != nil {
		return ChangePasswordResult{}, fmt.Errorf("get vault config: %w", err)
	}

	// Verify the current password matches what's unlocked.
	currentParams := argon2ParamsFrom(config)
	verifyKey := vaultcrypto.DeriveKey(params.CurrentPassword, config.Salt, currentParams)
	if !vaultcrypto.CheckVerificationBlob(verifyKey, config.VerificationBlob, config.VerificationNonce) {
		vaultcrypto.ZeroKey(verifyKey)
		return ChangePasswordResult{}, ErrIncorrectCurrentPassword
	}
	vaultcrypto.ZeroKey(verifyKey)

	// Generate new salt and derive new key.
	newSalt, err := vaultcrypto.GenerateSalt()
	if err != nil {
		return ChangePasswordResult{}, fmt.Errorf("generate salt: %w", err)
	}

	newKey := vaultcrypto.DeriveKey(params.NewPassword, newSalt, currentParams)
	defer vaultcrypto.ZeroKey(newKey)

	// Re-encrypt all entries inside a transaction so a partial failure
	// doesn't leave some entries on the old key and some on the new.
	tx, err := params.VaultDB.Db.BeginTx(ctx, nil)
	if err != nil {
		return ChangePasswordResult{}, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	qtx := params.VaultDB.Queries.WithTx(tx)

	entries, err := qtx.ListAllVaultEntriesForReEncrypt(ctx)
	if err != nil {
		return ChangePasswordResult{}, fmt.Errorf("list entries for re-encrypt: %w", err)
	}

	for _, entry := range entries {
		plaintext, err := vaultcrypto.Decrypt(params.OldKey, entry.Ciphertext, entry.Nonce)
		if err != nil {
			return ChangePasswordResult{}, fmt.Errorf("decrypt entry %d: %w", entry.ID, err)
		}

		var check json.RawMessage
		if err := json.Unmarshal(plaintext, &check); err != nil {
			return ChangePasswordResult{}, fmt.Errorf("corrupt entry %d: %w", entry.ID, err)
		}

		newCiphertext, newNonce, err := vaultcrypto.Encrypt(newKey, plaintext)
		if err != nil {
			return ChangePasswordResult{}, fmt.Errorf("re-encrypt entry %d: %w", entry.ID, err)
		}

		if err := qtx.UpdateVaultEntryCiphertext(ctx, db.UpdateVaultEntryCiphertextParams{
			Ciphertext: newCiphertext,
			Nonce:      newNonce,
			ID:         entry.ID,
		}); err != nil {
			return ChangePasswordResult{}, fmt.Errorf("save re-encrypted entry %d: %w", entry.ID, err)
		}
	}

	newVerBlob, newVerNonce, err := vaultcrypto.MakeVerificationBlob(newKey)
	if err != nil {
		return ChangePasswordResult{}, fmt.Errorf("create verification blob: %w", err)
	}

	if err := qtx.UpdateVaultConfigPassword(ctx, db.UpdateVaultConfigPasswordParams{
		Salt:              newSalt,
		VerificationBlob:  newVerBlob,
		VerificationNonce: newVerNonce,
	}); err != nil {
		return ChangePasswordResult{}, fmt.Errorf("update vault config: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return ChangePasswordResult{}, fmt.Errorf("commit tx: %w", err)
	}

	// Re-unlock with the new key.
	sessionKey := vaultcrypto.DeriveKey(params.NewPassword, newSalt, currentParams)
	params.Session.Unlock(sessionKey, time.Duration(config.AutoLockSeconds)*time.Second)
	vaultcrypto.ZeroKey(sessionKey)

	return ChangePasswordResult{Changed: true, ReEncrypted: len(entries)}, nil
}

// argon2ParamsFrom reads back the key-derivation cost this vault was set up
// with, so a vault created under older settings still unlocks.
func argon2ParamsFrom(config db.VaultConfig) vaultcrypto.Argon2Params {
	return vaultcrypto.Argon2Params{
		Memory:      uint32(config.Argon2Memory),
		Iterations:  uint32(config.Argon2Iterations),
		Parallelism: uint8(config.Argon2Parallelism),
	}
}
