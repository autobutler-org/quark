package authutil

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"

	"github.com/autobutler-org/quark/internal/db"
)

// inTx runs fn against queries bound to one transaction, committing only if fn
// succeeds.
func inTx(ctx context.Context, database *db.DatabaseSqlc, fn func(*db.Queries) error) error {
	tx, err := database.Db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(database.Queries.WithTx(tx)); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// ensureAnotherActiveAdmin returns ErrLastAdmin when target is the only active
// admin, so demoting, disabling or deleting it would leave the Quark with none
// (#1909). Any other target passes, including a non-admin or a disabled admin.
func ensureAnotherActiveAdmin(ctx context.Context, queries *db.Queries, target db.User) error {
	if target.IsAdmin == 0 || target.Status != StatusActive {
		return nil
	}
	others, err := queries.CountOtherActiveAdmins(ctx, target.ID)
	if err != nil {
		return fmt.Errorf("count admins: %w", err)
	}
	if others == 0 {
		return ErrLastAdmin
	}
	return nil
}

// firstRecoveryPhrase gives an account with no recovery credential a phrase,
// and returns it; an account that already has a phrase or a recovery key gets
// "". Only the sign-in whose write lands returns the phrase, so two at once
// cannot both show it.
func firstRecoveryPhrase(ctx context.Context, queries *db.Queries, user db.User) (string, error) {
	if user.RecoveryPhraseHash != "" || user.RecoveryKeyHash != "" {
		return "", nil
	}
	phrase, err := GenerateRecoveryPhrase()
	if err != nil {
		return "", err
	}
	hash, err := HashPassword(phrase)
	if err != nil {
		return "", err
	}
	set, err := queries.SetRecoveryPhraseIfUnset(ctx, db.SetRecoveryPhraseIfUnsetParams{
		RecoveryPhraseHash: hash,
		ID:                 user.ID,
	})
	if err != nil {
		return "", fmt.Errorf("store recovery phrase: %w", err)
	}
	if set == 0 {
		return "", nil
	}
	return phrase, nil
}

// usernamePattern is what a new account's username must match. A username
// also names a folder and a URL path segment, so it cannot hold a slash, start
// with a dot, or be ".." (#1908). Accounts created before the rule keep theirs.
var usernamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{0,31}$`)

// validateUsername returns ErrInvalidUsername for a username a new account
// cannot have.
func validateUsername(username string) error {
	if !usernamePattern.MatchString(username) {
		return ErrInvalidUsername
	}
	return nil
}

// statusError is the error a sign-in gets for an account's status, nil for an
// active account. A status the table's CHECK should keep out is refused like a
// disabled one.
func statusError(status string) error {
	switch status {
	case StatusActive:
		return nil
	case StatusPending:
		return ErrAccountPending
	default:
		return ErrAccountDisabled
	}
}

// mountsDirName is the directory under the data directory where external
// devices are mounted.
const mountsDirName = "mounts"

// homeRelPath is where an account's home sits: users/<username>, the path its
// owner grant is written on. ListAccountsMissingHome spells the same path in
// SQL, so the two have to agree.
func homeRelPath(username string) string {
	return path.Join(UsersDirName, username)
}

// grantHome makes an account the owner of its home.
//
// Written straight to the table rather than through accessutil: that grants on
// behalf of a caller, and the caller here is an admin or the Quark itself,
// neither of which needs a row.
func grantHome(ctx context.Context, queries *db.Queries, username string, userID int64) error {
	if err := queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: homeRelPath(username),
		UserID:  sql.NullInt64{Int64: userID, Valid: true},
		Level:   "owner",
	}); err != nil {
		return fmt.Errorf("grant the home of %q: %w", username, err)
	}
	return nil
}

// createHome makes an account's home under filesDir and grants it, on every
// path that lands an account: setup, an admin's create, and an approval
// (#1908). The directory and the grant are made together because an account
// with a home it does not own cannot write to it, which is the same to its
// owner as having no home at all.
//
// It returns the home's path relative to filesDir and the directory it made,
// which a caller whose transaction then fails removes. An existing home is
// adopted, not refused: the users table is what says whether a username is
// taken, and a folder is not an account. An admin may make users/<name> and
// fill it before the account exists, and whoever gets that name gets that
// folder. madeDir is empty for an adopted home, so a failed creation never
// removes a folder it did not make.
func createHome(ctx context.Context, queries *db.Queries, filesDir, username string, userID int64) (relPath, madeDir string, err error) {
	if filesDir == "" {
		return "", "", errors.New("files directory not set")
	}
	// The users parent is shared by every home, so MkdirAll it: it already
	// existing is not a conflict.
	if err := os.MkdirAll(filepath.Join(filesDir, UsersDirName), 0o755); err != nil {
		return "", "", fmt.Errorf("create users folder: %w", err)
	}
	// The username is validated, so it is one path segment and cannot climb
	// out of filesDir.
	home := filepath.Join(filesDir, UsersDirName, username)
	switch err := os.Mkdir(home, 0o755); {
	case err == nil:
		madeDir = home
	case errors.Is(err, os.ErrExist):
		// Adopted. Mkdir rather than MkdirAll so a non-directory in the way
		// still fails below instead of passing as a home.
		if info, statErr := os.Stat(home); statErr != nil || !info.IsDir() {
			return "", "", fmt.Errorf("create the home of %q: %s is not a folder", username, homeRelPath(username))
		}
	default:
		return "", "", fmt.Errorf("create the home of %q: %w", username, err)
	}
	// The grant is on the home alone. users/ gets none: breadcrumb visibility
	// already shows the path to someone granted beneath it, and it stays
	// admin-only otherwise.
	if err := grantHome(ctx, queries, username, userID); err != nil {
		// A directory this call made is reported so the caller removes it; the
		// transaction this runs in is about to roll the grant back.
		return "", madeDir, err
	}
	return homeRelPath(username), madeDir, nil
}

// pruneMountPoints removes the empty per-device directories under
// <dataDir>/mounts and nothing else.
//
// These are real mount targets: enabling a USB device creates
// <dataDir>/mounts/<serial> and mounts a partition onto it. Recursing into that
// tree with RemoveAll would delete straight through the mount into the user's
// external drive — the exact data that stays untouched unless devices=true is
// passed, and more of it than even devices=true authorizes, since that only
// reaches the quark data directory on a drive. os.Remove refuses a directory
// that is not empty, so a still-mounted or still-populated target survives and
// only the stale scaffolding goes.
func pruneMountPoints(dataDir string) error {
	mountsDir := filepath.Join(dataDir, mountsDirName)

	entries, err := os.ReadDir(mountsDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("failed to read mount points: %w", err)
	}

	for _, entry := range entries {
		// Deliberately unchecked: a non-empty directory is a live mount or a
		// populated target, and leaving it is the correct outcome.
		_ = os.Remove(filepath.Join(mountsDir, entry.Name()))
	}
	return nil
}

// authSaltSize and authKeySize are the decoded lengths, in bytes, of a
// key-derivation salt and of the auth key a client derives with it (#2430).
const (
	authSaltSize = 16
	authKeySize  = 32
)

// deterministicSalt is the salt for a username that has none stored: the
// first 16 bytes of HMAC-SHA256(secret, username), as standard base64. The
// username is used exactly as Login looks it up, with no folding.
func deterministicSalt(saltSecret func() ([]byte, error), username string) (string, error) {
	if saltSecret == nil {
		return "", errors.New("salt secret not available")
	}
	secret, err := saltSecret()
	if err != nil {
		return "", fmt.Errorf("read the salt secret: %w", err)
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(username))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil)[:authSaltSize]), nil
}

// validateAuthKey returns ErrInvalidAuthKey unless authKey is the standard
// base64 of exactly 32 bytes.
func validateAuthKey(authKey string) error {
	return validateKey(authKey, ErrInvalidAuthKey)
}

// validateKey returns invalid unless key is the standard base64 of exactly 32
// bytes, the shape of an auth key and of a recovery key. That is 44
// characters, under bcrypt's 72-byte limit, so the encoded key is what gets
// hashed.
func validateKey(key string, invalid error) error {
	if decoded, err := base64.StdEncoding.DecodeString(key); err != nil || len(decoded) != authKeySize {
		return invalid
	}
	return nil
}

// recoveryKeyHashFor validates a new recovery key and returns its hash, or ""
// when there is none. A recovery key is derived with the auth salt, so it is
// refused beside anything but an auth key (#2430).
func recoveryKeyHashFor(authKey, recoveryKey string) (string, error) {
	if recoveryKey == "" {
		return "", nil
	}
	if authKey == "" {
		return "", ErrRecoveryKeyNeedsAuthKey
	}
	if err := validateKey(recoveryKey, ErrInvalidRecoveryKey); err != nil {
		return "", err
	}
	return HashPassword(recoveryKey)
}

// newRecovery is the recovery credential a new account starts with: the hash
// of the recovery key its client sent, or else a phrase the Quark generates,
// returned to show once, and its hash.
func newRecovery(authKey, recoveryKey string) (phrase, phraseHash, keyHash string, err error) {
	if keyHash, err = recoveryKeyHashFor(authKey, recoveryKey); err != nil || keyHash != "" {
		return "", "", keyHash, err
	}
	if phrase, err = GenerateRecoveryPhrase(); err != nil {
		return "", "", "", err
	}
	phraseHash, err = HashPassword(phrase)
	return phrase, phraseHash, "", err
}

// newCredentials validates the one credential a new account or a recovery
// gives and returns what to store for it. A password yields its hash alone; an
// auth key yields its hash and the deterministic salt for username, and leaves
// the password hash empty, which no password matches.
func newCredentials(username, password, authKey string, saltSecret func() ([]byte, error)) (passwordHash, authKeyHash, authSalt string, err error) {
	switch {
	case password == "" && authKey == "":
		return "", "", "", ErrCredentialRequired
	case password != "" && authKey != "":
		return "", "", "", ErrCredentialConflict
	case authKey == "":
		if len(password) < 8 {
			return "", "", "", ErrPasswordTooShort
		}
		passwordHash, err = HashPassword(password)
		return passwordHash, "", "", err
	}
	if err := validateAuthKey(authKey); err != nil {
		return "", "", "", err
	}
	if authSalt, err = deterministicSalt(saltSecret, username); err != nil {
		return "", "", "", err
	}
	authKeyHash, err = HashPassword(authKey)
	return "", authKeyHash, authSalt, err
}

// upgradeToAuthKey gives an account that signs in by password its auth key,
// with the deterministic salt /auth/salt answered for it. The password hash
// stays, so a client that still sends the password keeps signing in.
func upgradeToAuthKey(ctx context.Context, queries *db.Queries, user db.User, authKey string, saltSecret func() ([]byte, error)) error {
	salt, err := deterministicSalt(saltSecret, user.Username)
	if err != nil {
		return err
	}
	hash, err := HashPassword(authKey)
	if err != nil {
		return err
	}
	if err := queries.SetAuthKeyIfUnset(ctx, db.SetAuthKeyIfUnsetParams{AuthKeyHash: hash, AuthSalt: salt, ID: user.ID}); err != nil {
		return fmt.Errorf("store the auth key: %w", err)
	}
	return nil
}

// matchesCredential reports whether secret is the account's password or its
// auth key. Re-confirmation and HTTP Basic take either in the one password
// field (#2430); an empty hash matches nothing.
func matchesCredential(user db.User, secret string) bool {
	return CheckPassword(secret, user.PasswordHash) || CheckPassword(secret, user.AuthKeyHash)
}
