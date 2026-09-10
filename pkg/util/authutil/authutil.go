// Package authutil handles single-user authentication: password hashing,
// recovery phrases, first-boot setup, login, session issue and validation,
// and admin role management.
package authutil

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"golang.org/x/crypto/bcrypt"
)

const (
	bcryptCost       = 12
	sessionTokenSize = 32 // bytes → 64 hex chars
	recoveryWords    = 6
)

// SetupParams contains parameters for first-boot user setup.
type SetupParams struct {
	Username string
	Password string
}

// SetupResult contains the result of first-boot setup.
type SetupResult struct {
	SessionToken   string
	RecoveryPhrase string // shown once — caller must surface to user
}

// LoginParams contains parameters for login.
type LoginParams struct {
	Username string
	Password string
}

// LoginResult contains the result of a successful login.
type LoginResult struct {
	SessionToken string
}

// RecoverParams contains parameters for password recovery.
type RecoverParams struct {
	RecoveryPhrase string
	NewPassword    string
}

// SessionInfo is a safe, token-free representation of an active session
// returned to the caller. The ID is the hex-encoded SHA-256 of the raw token
// so clients can reference a session for revocation without exposing the token.
type SessionInfo struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"createdAt"`
	ExpiresAt time.Time `json:"expiresAt"`
}

// HashPassword hashes a plaintext password using bcrypt.
func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return "", fmt.Errorf("failed to hash password: %w", err)
	}
	return string(hash), nil
}

// CheckPassword verifies a plaintext password against a bcrypt hash.
func CheckPassword(password, hash string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

// GenerateSessionToken returns a cryptographically random hex session token.
func GenerateSessionToken() (string, error) {
	b := make([]byte, sessionTokenSize)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("failed to generate session token: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// GenerateRecoveryPhrase generates a random 6-word recovery phrase from the
// built-in wordlist. The phrase is shown to the user exactly once at setup.
//
// Entropy note: the built-in wordlist has 256 words, giving ~8 bits per word
// and ~48 bits of entropy for a 6-word phrase. This is sufficient for a
// single-user local device with bcrypt verification (not a high-value online
// target). BIP39 (2048 words, ~77 bits) would be stronger but the tradeoff
// is intentional — shorter phrases are easier for users to write down correctly.
func GenerateRecoveryPhrase() (string, error) {
	words := make([]string, recoveryWords)
	listLen := int64(len(wordlist))
	buf := make([]byte, 8)
	for i := range words {
		if _, err := rand.Read(buf); err != nil {
			return "", fmt.Errorf("failed to generate recovery phrase: %w", err)
		}
		// Convert 8 random bytes to uint64, mod by wordlist length
		var n uint64
		for _, b := range buf {
			n = n<<8 | uint64(b)
		}
		words[i] = wordlist[n%uint64(listLen)]
	}
	return strings.Join(words, "-"), nil
}

// NormalizeRecoveryPhrase lowercases and trims a recovery phrase for comparison.
func NormalizeRecoveryPhrase(phrase string) string {
	return strings.ToLower(strings.TrimSpace(phrase))
}

// IsSetupComplete returns true if at least one user exists.
func IsSetupComplete(ctx context.Context, queries *db.Queries) (bool, error) {
	count, err := queries.CountUsers(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to count users: %w", err)
	}
	return count > 0, nil
}

// Setup creates the first user and returns a session token + recovery phrase.
// Returns an error if setup has already been completed.
func Setup(ctx context.Context, queries *db.Queries, params SetupParams) (*SetupResult, error) {
	if params.Username == "" {
		return nil, fmt.Errorf("username is required")
	}
	if len(params.Password) < 8 {
		return nil, fmt.Errorf("password must be at least 8 characters")
	}

	complete, err := IsSetupComplete(ctx, queries)
	if err != nil {
		return nil, err
	}
	if complete {
		return nil, fmt.Errorf("setup already complete")
	}

	passwordHash, err := HashPassword(params.Password)
	if err != nil {
		return nil, err
	}

	recoveryPhrase, err := GenerateRecoveryPhrase()
	if err != nil {
		return nil, err
	}

	recoveryHash, err := HashPassword(recoveryPhrase)
	if err != nil {
		return nil, err
	}

	user, err := queries.CreateUser(ctx, db.CreateUserParams{
		Username:           params.Username,
		PasswordHash:       passwordHash,
		RecoveryPhraseHash: recoveryHash,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	// First user is automatically the admin.
	if err := queries.SetUserAdmin(ctx, db.SetUserAdminParams{
		IsAdmin:  1,
		Username: user.Username,
	}); err != nil {
		return nil, fmt.Errorf("promote first user to admin: %w", err)
	}

	token, err := newSession(ctx, queries, user.ID)
	if err != nil {
		return nil, err
	}

	return &SetupResult{
		SessionToken:   token,
		RecoveryPhrase: recoveryPhrase,
	}, nil
}

// Login validates credentials and returns a session token.
func Login(ctx context.Context, queries *db.Queries, params LoginParams) (*LoginResult, error) {
	user, err := queries.GetUserByUsername(ctx, params.Username)
	if err != nil {
		// Don't leak whether the username exists
		return nil, fmt.Errorf("invalid credentials")
	}

	if !CheckPassword(params.Password, user.PasswordHash) {
		return nil, fmt.Errorf("invalid credentials")
	}

	token, err := newSession(ctx, queries, user.ID)
	if err != nil {
		return nil, err
	}

	return &LoginResult{SessionToken: token}, nil
}

// ValidateSession checks a session token and returns the username and user id
// if valid. The raw token is hashed before the DB lookup — tokens are never
// stored plaintext. The id comes from the sessions row already being read, so
// callers that need it pay no extra query.
//
// Using a session also renews it; see renewSession.
func ValidateSession(ctx context.Context, queries *db.Queries, token string) (string, int64, error) {
	digest := hashToken(token)
	session, err := queries.GetSession(ctx, digest)
	if err != nil {
		return "", 0, fmt.Errorf("invalid or expired session")
	}
	renewSession(ctx, queries, digest, session)
	return session.Username, session.UserID, nil
}

// ValidateBasicAuth checks a username/password pair against the user database.
// Returns the username and user id if valid, or an error if not. Unlike Login,
// this does not create a session — each request authenticates independently.
func ValidateBasicAuth(ctx context.Context, queries *db.Queries, username, password string) (string, int64, error) {
	user, err := queries.GetUserByUsername(ctx, username)
	if err != nil {
		return "", 0, fmt.Errorf("invalid credentials")
	}
	if !CheckPassword(password, user.PasswordHash) {
		return "", 0, fmt.Errorf("invalid credentials")
	}
	return user.Username, user.ID, nil
}

// Logout deletes a session token.
func Logout(ctx context.Context, queries *db.Queries, token string) error {
	return queries.DeleteSession(ctx, hashToken(token))
}

// Recover resets a user's password using their recovery phrase.
func Recover(ctx context.Context, queries *db.Queries, params RecoverParams) (*LoginResult, error) {
	if len(params.NewPassword) < 8 {
		return nil, fmt.Errorf("password must be at least 8 characters")
	}

	// We need to check the recovery phrase against all users (there's only one in single-user mode)
	// Get all users — for now just check the first/only user
	count, err := queries.CountUsers(ctx)
	if err != nil || count == 0 {
		return nil, fmt.Errorf("invalid recovery phrase")
	}

	// TODO(#350): multi-user recovery needs to match the recovery phrase to a
	// specific user. For now, single-user mode — find the first (only) user.
	user, err := queries.GetFirstUser(ctx)
	if err != nil {
		return nil, fmt.Errorf("invalid recovery phrase")
	}

	normalized := NormalizeRecoveryPhrase(params.RecoveryPhrase)
	if !CheckPassword(normalized, user.RecoveryPhraseHash) {
		return nil, fmt.Errorf("invalid recovery phrase")
	}

	newHash, err := HashPassword(params.NewPassword)
	if err != nil {
		return nil, err
	}

	if err := queries.UpdateUserPassword(ctx, db.UpdateUserPasswordParams{
		ID:           user.ID,
		PasswordHash: newHash,
	}); err != nil {
		return nil, fmt.Errorf("failed to update password: %w", err)
	}

	// Invalidate all existing sessions for this user
	if err := queries.DeleteUserSessions(ctx, user.ID); err != nil {
		return nil, fmt.Errorf("failed to invalidate sessions: %w", err)
	}

	token, err := newSession(ctx, queries, user.ID)
	if err != nil {
		return nil, err
	}

	return &LoginResult{SessionToken: token}, nil
}

// ListActiveSessions returns all non-expired sessions for the given user.
// Because tokens are stored as SHA-256 digests, the digest itself is used
// as the opaque session ID exposed to clients.
func ListActiveSessions(ctx context.Context, queries *db.Queries, userID int64) ([]SessionInfo, error) {
	rows, err := queries.ListActiveSessionsForUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list sessions: %w", err)
	}
	out := make([]SessionInfo, 0, len(rows))
	for _, s := range rows {
		out = append(out, SessionInfo{
			// s.Token is already the SHA-256 digest (stored that way in newSession).
			ID:        s.Token,
			CreatedAt: s.CreatedAt,
			ExpiresAt: s.ExpiresAt,
		})
	}
	return out, nil
}

// RevokeSession deletes the session whose stored digest matches the given id,
// scoped to the given user. Returns true if a session was deleted, false if
// no matching session was found.
func RevokeSession(ctx context.Context, queries *db.Queries, userID int64, id string) (bool, error) {
	rows, err := queries.ListActiveSessionsForUser(ctx, userID)
	if err != nil {
		return false, fmt.Errorf("failed to list sessions: %w", err)
	}
	for _, s := range rows {
		// s.Token is the stored digest; id is also a digest.
		if s.Token == id {
			if err := queries.DeleteSession(ctx, s.Token); err != nil {
				return false, fmt.Errorf("failed to delete session: %w", err)
			}
			return true, nil
		}
	}
	return false, nil
}

// RevokeAllSessions deletes all sessions for the given user.
func RevokeAllSessions(ctx context.Context, queries *db.Queries, userID int64) error {
	if err := queries.DeleteUserSessions(ctx, userID); err != nil {
		return fmt.Errorf("failed to revoke sessions: %w", err)
	}
	return nil
}

// PurgeExpiredSessions removes all sessions whose expiry has passed. (#1330)
// GetSession already guards against expired tokens, so this is a housekeeping
// operation rather than a security gate.
func PurgeExpiredSessions(ctx context.Context, queries *db.Queries) error {
	if err := queries.DeleteExpiredSessions(ctx); err != nil {
		return fmt.Errorf("purge expired sessions: %w", err)
	}
	return nil
}

// IsAdmin returns true if the given username has the admin role.
// Returns false (not an error) for unknown users.
func IsAdmin(ctx context.Context, queries *db.Queries, username string) (bool, error) {
	val, err := queries.IsUserAdmin(ctx, username)
	if err != nil {
		return false, fmt.Errorf("check admin: %w", err)
	}
	return val != 0, nil
}

// PromoteToAdmin grants admin to the given username.
func PromoteToAdmin(ctx context.Context, queries *db.Queries, username string) error {
	if _, err := queries.PromoteToAdmin(ctx, username); err != nil {
		return fmt.Errorf("promote %q to admin: %w", username, err)
	}
	return nil
}

// DemoteFromAdmin removes admin from the given username, refusing if they are
// the last admin.
func DemoteFromAdmin(ctx context.Context, queries *db.Queries, username string) error {
	count, err := queries.GetAdminCount(ctx)
	if err != nil {
		return fmt.Errorf("count admins: %w", err)
	}
	if count <= 1 {
		return errors.New("cannot demote the last admin")
	}
	if _, err := queries.DemoteFromAdmin(ctx, username); err != nil {
		return fmt.Errorf("demote %q: %w", username, err)
	}
	return nil
}

// DeleteAccountParams selects what a delete-account request wipes. All three
// aspects are opt-in: a request that selects none is rejected rather than
// treated as "everything", so a truncated or mis-serialized call fails closed.
type DeleteAccountParams struct {
	Database       *db.DatabaseSqlc
	Queries        *db.Queries
	HealthDatabase *db.DatabaseRaw
	// DataDir is the appliance's own data directory. Production passes
	// storageutil.GetDataDir(); tests pass a temporary directory.
	DataDir string
	// DeviceDataDirs are the quark data directories on attached external
	// devices — each one a <mount>/quark/data. Only the quark-owned subtree
	// belongs here, never a whole mount point: a factory reset erases what
	// Quark put on a drive, not the rest of the user's drive.
	DeviceDataDirs []string
	Username       string
	UserID         int64
	// DeleteAccount removes the caller's own users row. It is the aspect App
	// Store Review Guideline 5.1.1(v) requires: an app that lets a user create
	// an account must let them delete it from inside the app. The factory-reset
	// aspects do not satisfy it — DeleteDatabase erases every user's data to
	// remove one account, which is the wrong operation on a shared appliance.
	DeleteAccount  bool
	DeleteDatabase bool
	DeleteFiles    bool
	DeleteDevices  bool
}

// DeleteAccountResult reports which aspects were actually wiped.
type DeleteAccountResult struct {
	AccountDeleted  bool
	DatabaseDeleted bool
	FilesDeleted    bool
	DevicesDeleted  bool
	// FilesRetained is true when the account or the database went but the file
	// tree stayed. That combination hands the stored files to whoever sets the
	// appliance up next: with no users left the setup flow re-triggers, and the
	// new owner has a normal account on an appliance still holding the previous
	// owner's files. It is the default shape of an App Store account deletion,
	// which is exactly why it is surfaced rather than left to be inferred.
	FilesRetained bool
}

// DeleteAccount wipes the selected aspects of the appliance and revokes every
// session, leaving the caller logged out.
//
// DeleteAccount removes the caller's own users row and nothing else. The other
// three aspects are a factory reset rather than a per-user delete: users is the
// only table in the schema that has a user at all — photos, the vault, device
// roles and the search index carry no user_id, and vault_location is a
// CHECK (id = 1) singleton — so "delete this user's data" is not expressible
// against it (#1759). Only the account row itself is.
//
// The aspects map onto disk as:
//
//   - DeleteAccount: the caller's row in users. Deleting the last one takes the
//     appliance back to first boot, because IsSetupComplete is COUNT(users) > 0,
//     so the setup flow re-triggers rather than the appliance becoming
//     unreachable.
//
//   - DeleteDatabase: the appliance's databases, quark.db and quark.health.db.
//     An internal vault lives in quark.db itself (migration 005), so it goes
//     with them; a separate vault.db file exists only on an external device.
//
//   - DeleteFiles: the file trees the appliance owns, <dataDir>/files and the
//     mount-point scaffolding under <dataDir>/mounts.
//
//   - DeleteDevices: the quark data directory on each attached external
//     device, which is what carries an off-appliance vault.
//
// Order is deliberate. Sessions go first so no client keeps operating against a
// half-erased appliance. Deleting the users row would take them too —
// sessions.user_id declares ON DELETE CASCADE (001_auth) and connections carry
// _foreign_keys=on, so the cascade actually runs — but the account aspect is
// opt-in and the other three do not touch the users table, so a factory reset
// without it would otherwise leave every session live against the wiped
// appliance.
//
// The account row goes next, before the destructive filesystem work: a caller
// who asked for their account to be deleted must not be left with it alive
// because a later aspect failed. The databases go last because a database reset
// that fails after the files are gone leaves the user a working database and a
// retry path, whereas the reverse leaves orphaned files behind a fresh database
// with no session to retry from, and because the audit trail should outlive
// everything it describes.
//
// DeleteAccount combined with DeleteDatabase is redundant but not contradictory:
// the reset drops the users table wholesale a few steps later. The row is still
// deleted first so that a failure in between cannot leave the account standing.
//
// Every step is idempotent: removing a directory that is already gone,
// re-migrating an already-empty database, and dropping objects from an already
// empty one all succeed.
func DeleteAccount(ctx context.Context, params DeleteAccountParams) (DeleteAccountResult, error) {
	var result DeleteAccountResult

	if !params.DeleteAccount && !params.DeleteDatabase && !params.DeleteFiles && !params.DeleteDevices {
		return result, errors.New("no aspect selected: pass account=true, database=true, files=true, devices=true, or any combination")
	}
	if params.Database == nil || params.Queries == nil {
		return result, errors.New("database not initialized")
	}

	// Audited before anything is touched, and to the log rather than a table:
	// a record of the wipe stored in the database being wiped is gone at
	// exactly the moment it becomes useful (#1759).
	slog.Warn("delete account requested",
		"username", params.Username,
		"account", params.DeleteAccount,
		"database", params.DeleteDatabase,
		"files", params.DeleteFiles,
		"devices", params.DeleteDevices,
	)

	if err := RevokeAllSessions(ctx, params.Queries, params.UserID); err != nil {
		return result, err
	}

	if params.DeleteAccount {
		if err := params.Queries.DeleteUser(ctx, params.UserID); err != nil {
			return result, fmt.Errorf("failed to delete account: %w", err)
		}
		result.AccountDeleted = true
	}

	if params.DeleteFiles {
		if err := os.RemoveAll(storageutil.ConstructFilesDir(params.DataDir)); err != nil {
			return result, fmt.Errorf("failed to delete files: %w", err)
		}
		if err := pruneMountPoints(params.DataDir); err != nil {
			return result, err
		}
		result.FilesDeleted = true
	}

	if params.DeleteDevices {
		for _, deviceDataDir := range params.DeviceDataDirs {
			if err := os.RemoveAll(deviceDataDir); err != nil {
				return result, fmt.Errorf("failed to delete device data at %s: %w", deviceDataDir, err)
			}
		}
		result.DevicesDeleted = true
	}

	if params.DeleteDatabase {
		if params.HealthDatabase != nil {
			if err := db.ResetRawDatabase(params.HealthDatabase); err != nil {
				return result, fmt.Errorf("failed to reset health database: %w", err)
			}
		}
		if err := db.ResetDatabase(params.Database); err != nil {
			return result, fmt.Errorf("failed to reset database: %w", err)
		}
		result.DatabaseDeleted = true
	}

	// Recorded because it is the security-relevant outcome, not merely a summary
	// of the request: the files outliving the account that owned them is what a
	// later "how did the new owner see those?" question turns on.
	result.FilesRetained = (result.AccountDeleted || result.DatabaseDeleted) && !result.FilesDeleted

	slog.Warn("delete account completed",
		"username", params.Username,
		"accountDeleted", result.AccountDeleted,
		"filesRetained", result.FilesRetained,
		"databaseDeleted", result.DatabaseDeleted,
		"filesDeleted", result.FilesDeleted,
		"devicesDeleted", result.DevicesDeleted,
	)
	return result, nil
}
