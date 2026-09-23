package authutil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sync"

	"github.com/autobutler-org/quark/internal/db"
)

// setupMu serializes founding setup so two first-boot requests cannot both
// observe an empty users table and both become admin (quark-project #118).
var setupMu sync.Mutex

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

// firstRecoveryPhrase gives an account with no recovery phrase one, and
// returns it; an account that already has one gets "". Only the sign-in whose
// write lands returns the phrase, so two at once cannot both show it.
func firstRecoveryPhrase(ctx context.Context, queries *db.Queries, user db.User) (string, error) {
	if user.RecoveryPhraseHash != "" {
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
