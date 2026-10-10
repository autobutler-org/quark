package authutil

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
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

// createHome makes an account's home in files and grants it, on every path
// that lands an account: setup, an admin's create, and an approval (#1908).
// The directory and the grant are made together because an account with a
// home it does not own cannot write to it, which is the same to its owner as
// having no home at all.
//
// It returns the home's path relative to the files root and the directory it
// made, which a caller whose transaction then fails removes with
// RemoveMadeFolder. An existing home is adopted, not refused: the users table
// is what says whether a username is taken, and a folder is not an account. An
// admin may make users/<name> and fill it before the account exists, and
// whoever gets that name gets that folder. madeDir is empty for an adopted
// home, so a failed creation never removes a folder it did not make.
func createHome(ctx context.Context, queries *db.Queries, files vfs.VFS, username string, userID int64) (relPath, madeDir string, err error) {
	// The username is validated, so it is one path segment and cannot climb
	// out of the files root.
	home := homeRelPath(username)
	made, err := MakeFolder(ctx, files, home)
	if err != nil {
		return "", "", fmt.Errorf("create the home of %q: %w", username, err)
	}
	if made {
		madeDir = home
	}
	// The grant is on the home alone. users/ gets none: breadcrumb visibility
	// already shows the path to someone granted beneath it, and it stays
	// admin-only otherwise.
	if err := grantHome(ctx, queries, username, userID); err != nil {
		// A directory this call made is reported so the caller removes it; the
		// transaction this runs in is about to roll the grant back.
		return "", madeDir, err
	}
	return home, madeDir, nil
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
// bytes, the shape of an auth key and of a recovery key. The encoded key, 44
// characters, is what gets hashed.
func validateKey(key string, invalid error) error {
	if decoded, err := base64.StdEncoding.DecodeString(key); err != nil || len(decoded) != authKeySize {
		return invalid
	}
	return nil
}

// isRawSecret reports whether secret, sent where an auth key goes, is a raw
// password instead: set, but not shaped like a key (#2430). An empty secret is
// not one, and fails as a wrong key does.
func isRawSecret(secret string) bool {
	return secret != "" && validateAuthKey(secret) != nil
}

// recoveryKeyHashFor validates a new account's recovery key and returns its
// hash, or "" when there is none (#2430).
func recoveryKeyHashFor(recoveryKey string) (string, error) {
	if recoveryKey == "" {
		return "", nil
	}
	if err := validateKey(recoveryKey, ErrInvalidRecoveryKey); err != nil {
		return "", err
	}
	return HashKey(recoveryKey)
}

// errUpgradeFailed refuses a sign-in whose password was right but whose move
// to the auth key did not land (#2430). The password hash is cleared only by
// that write, so signing in anyway would leave the account on its password.
var errUpgradeFailed error = serverutil.NewHttpError(http.StatusInternalServerError,
	"couldn't move the account to its auth key; try signing in again")

// upgradeToAuthKey moves an account that signs in by password to authKey,
// with the deterministic salt /auth/salt answered for it, and clears its
// password hash in the same write. A write that matches no row is a second
// sign-in having upgraded the account first. Every failure is logged and
// returned as errUpgradeFailed, so the cause stays out of the response.
func upgradeToAuthKey(ctx context.Context, queries *db.Queries, user db.User, authKey string, saltSecret func() ([]byte, error)) error {
	err := func() error {
		salt, err := deterministicSalt(saltSecret, user.Username)
		if err != nil {
			return err
		}
		hash, err := HashKey(authKey)
		if err != nil {
			return err
		}
		upgraded, err := queries.UpgradeToAuthKey(ctx, db.UpgradeToAuthKeyParams{AuthKeyHash: hash, AuthSalt: salt, ID: user.ID})
		if err != nil {
			return err
		}
		if upgraded == 0 {
			return errors.New("the account already has an auth key")
		}
		return nil
	}()
	if err != nil {
		slog.Warn("auth key upgrade failed", "username", user.Username, "error", err)
		return errUpgradeFailed
	}
	return nil
}

// normalizeRecoveryPhrase lowercases and trims a recovery phrase for
// comparison.
func normalizeRecoveryPhrase(phrase string) string {
	return strings.ToLower(strings.TrimSpace(phrase))
}

// newCredentials validates the auth key a new account or a recovery gives and
// returns its hash and the deterministic salt for username.
func newCredentials(username, authKey string, saltSecret func() ([]byte, error)) (authKeyHash, authSalt string, err error) {
	if err := validateAuthKey(authKey); err != nil {
		return "", "", err
	}
	if authSalt, err = deterministicSalt(saltSecret, username); err != nil {
		return "", "", err
	}
	authKeyHash, err = HashKey(authKey)
	return authKeyHash, authSalt, err
}

// loginFailed counts a wrong username or password toward guard's lockouts and
// logs it in one fixed shape, so a host-side fail2ban jail can match it too.
// The error is the same for both, so it does not reveal which was wrong. The
// username is left out of the log: people type passwords into that field.
func loginFailed(guard *ratelimitutil.LoginGuard, attempt ratelimitutil.LoginAttempt) error {
	guard.RecordFailure(attempt)
	slog.Warn("sign-in failed", "ip", attempt.IP)
	return fmt.Errorf("invalid credentials")
}

// unavailable logs a session or account lookup the database could not answer
// and returns ErrUnavailable in its place, so the cause reaches the log and
// stays out of the response (#2858). The caller has already set aside
// sql.ErrNoRows, which is an answer: the credential is wrong. Neither the
// token nor the username is logged.
func unavailable(lookup string, err error) error {
	slog.Warn("auth lookup failed", "lookup", lookup, "error", err)
	return ErrUnavailable
}

// keyHashPrefix marks a hash HashKey made. bcrypt's start with "$2", so the
// two are never mistaken for each other.
const keyHashPrefix = "sha256:"

// errNotAKey is HashKey's refusal. Every caller validates its key first and
// answers with its own error, so this one reaches nobody unless that is missed.
var errNotAKey = errors.New("only the base64 of 32 bytes is hashed as a key")

// checkAuthKey reports whether authKey is user's auth key. Every check of an
// auth key goes through here, because a key that matches a bcrypt hash, one
// stored before keys took SHA-256, has its row rewritten with HashKey so the
// next check is fast (#2765). The write matches only the hash that was just
// verified, so a credential changed in the meantime is left alone, and a
// failed one is logged, not returned: the key was right.
func checkAuthKey(ctx context.Context, queries *db.Queries, user db.User, authKey string) bool {
	if !CheckPassword(authKey, user.AuthKeyHash) {
		return false
	}
	if strings.HasPrefix(user.AuthKeyHash, keyHashPrefix) {
		return true
	}
	hash, err := HashKey(authKey)
	if err == nil {
		err = queries.RehashAuthKey(ctx, db.RehashAuthKeyParams{NewHash: hash, ID: user.ID, OldHash: user.AuthKeyHash})
	}
	if err != nil {
		slog.Warn("auth key rehash failed", "username", user.Username, "error", err)
	}
	return true
}

// guardedAccount is the credential check Login and AuthenticateBasic share,
// and returns the account it passed for. A locked-out attempt gets
// *TooManyAttemptsError before anything is looked up. An account with an auth
// key is checked by authKey; one with none is checked by password, which only
// Login sends. A wrong username or credential is counted toward a lockout,
// and the account's status is checked last. Recording the success is left to
// the caller, which may still have work that can fail.
//
// A lookup the database could not answer is ErrUnavailable. It is not a wrong
// guess, so it is not counted: a database error must not lock an account out.
func guardedAccount(ctx context.Context, queries *db.Queries, guard *ratelimitutil.LoginGuard, attempt ratelimitutil.LoginAttempt, authKey, password string) (db.User, error) {
	if wait := guard.Check(attempt).RetryAfter; wait > 0 {
		return db.User{}, &TooManyAttemptsError{RetryAfter: wait}
	}
	user, err := queries.GetUserByUsername(ctx, attempt.Account)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return db.User{}, unavailable("account", err)
	}
	if err != nil {
		// Don't leak whether the username exists
		return db.User{}, loginFailed(guard, attempt)
	}
	var matched bool
	if user.AuthKeyHash == "" && password != "" {
		matched = CheckPassword(password, user.PasswordHash)
	} else {
		matched = checkAuthKey(ctx, queries, user, authKey)
	}
	if !matched {
		return db.User{}, loginFailed(guard, attempt)
	}
	return user, statusError(user.Status)
}
