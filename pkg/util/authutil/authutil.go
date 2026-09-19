// Package authutil handles authentication: password hashing, recovery
// phrases, first-boot setup, login, session issue and validation, account
// status, and admin role management.
package authutil

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"golang.org/x/crypto/bcrypt"
)

const (
	bcryptCost       = 12
	sessionTokenSize = 32 // bytes → 64 hex chars
	recoveryWords    = 6
)

// Account statuses, as the users table spells them (#1908).
const (
	// StatusPending is an account request an admin has not approved yet.
	StatusPending = "pending"
	// StatusActive is an account that may sign in.
	StatusActive = "active"
	// StatusDisabled is an account an admin turned off. It keeps what it owns.
	StatusDisabled = "disabled"
)

// UsersDirName is the directory under the files directory that holds every
// account's home, so a username never collides with a top-level folder name
// (#2016).
const UsersDirName = "users"

// Errors a handler passes to the app unchanged. Their text is what a person
// reads, so they are returned bare rather than wrapped.
var (
	// ErrAccountPending refuses a sign-in to an account nobody has approved.
	ErrAccountPending = errors.New("your account request is waiting for approval")
	// ErrAccountDisabled refuses a sign-in to an account an admin turned off.
	ErrAccountDisabled = errors.New("this account is turned off")
	// ErrInvalidUsername refuses a username a new account cannot have.
	ErrInvalidUsername = errors.New("a username has up to 32 lowercase letters, numbers, dots, dashes or underscores, and starts with a letter or number")
	// ErrLastAdmin refuses a change that would leave no active admin.
	ErrLastAdmin = errors.New("this Quark needs at least one active admin")
	// ErrUserNotFound reports a username that names no account the action
	// applies to.
	ErrUserNotFound = errors.New("no account has that username")
	// ErrRequestNotFound reports a username that names no pending request.
	ErrRequestNotFound = errors.New("no account request has that username")
	// ErrUsernameTaken refuses a new account whose username an account or a
	// pending request already holds.
	ErrUsernameTaken = errors.New("that username is taken")
	// ErrAccessRequestsOff refuses an account request while an admin has
	// turned requests off, or before the Quark is set up.
	ErrAccessRequestsOff = errors.New("this Quark isn't taking account requests right now")
	// ErrPasswordTooShort refuses a password under eight characters.
	ErrPasswordTooShort = errors.New("password must be at least 8 characters")
	// ErrFolderExists refuses a home under users/ that would hand an existing
	// folder's contents to a new account. It never reports the shared users
	// parent every home sits in, only a home that is already taken.
	ErrFolderExists = errors.New("a folder with that name already exists")
	// ErrSelfAction refuses an admin action aimed at the admin's own account.
	ErrSelfAction = errors.New("use Settings to change your own account")
)

// DisableUserParams names the account an admin turns off.
type DisableUserParams struct {
	Database *db.DatabaseSqlc
	// ActorUserID is the admin acting, who cannot turn their own account off.
	ActorUserID int64
	Username    string
}

// DisableUserResult is empty; turning an account off has nothing to report.
type DisableUserResult struct{}

// EnableUserParams names the account an admin turns back on.
type EnableUserParams struct {
	Username string
}

// EnableUserResult is empty; turning an account on has nothing to report.
type EnableUserResult struct{}

// DeleteUserParams names an account to delete (#1909).
type DeleteUserParams struct {
	Database *db.DatabaseSqlc
	// ActorUserID is the admin deleting the account, who inherits what it
	// owned. Zero means the account is deleting itself, and its longest-standing
	// active admin inherits instead.
	ActorUserID int64
	Username    string
}

// DeleteUserResult reports where the deleted account's files went.
type DeleteUserResult struct {
	// HeirUserID owns what the account owned, zero when nobody was left to.
	HeirUserID          int64
	OwnerRowsReassigned int64
	// SetupReset is true when the account was the last one, so the Quark
	// returns to setup. Any pending requests went with it.
	SetupReset bool
}

// CreateUserParams is an account an admin adds (#1873).
type CreateUserParams struct {
	Database *db.DatabaseSqlc
	Username string
	Password string
	// FilesDir is the internal device's files directory, where the account's
	// home is made.
	FilesDir string
}

// CreateUserResult is the account that was added.
type CreateUserResult struct {
	UserID    int64
	CreatedAt time.Time
	// FolderPath is the home's path relative to FilesDir — users/<username>.
	FolderPath string
}

// RequestAccountParams asks for an account from the sign-in page (#1908).
type RequestAccountParams struct {
	Username string
	Password string
	// RequestsEnabled is the admin's access-request setting.
	RequestsEnabled bool
}

// RequestAccountResult carries the requester's recovery phrase, shown once.
type RequestAccountResult struct {
	RecoveryPhrase string
}

// ApproveRequestParams names the pending request an admin approves.
type ApproveRequestParams struct {
	Database *db.DatabaseSqlc
	Username string
	// FilesDir is the internal device's files directory, where the approved
	// account's home is made.
	FilesDir string
}

// ApproveRequestResult is the approved account's home.
type ApproveRequestResult struct {
	// FolderPath is the home's path relative to FilesDir — users/<username>.
	FolderPath string
}

// DenyRequestParams names the pending request an admin denies.
type DenyRequestParams struct {
	Username string
}

// DenyRequestResult is empty; a denial has nothing to report.
type DenyRequestResult struct{}

// SetupParams contains parameters for first-boot user setup.
type SetupParams struct {
	Database *db.DatabaseSqlc
	Username string
	Password string
	// FilesDir is the internal device's files directory, where the founding
	// admin's home is made.
	FilesDir string
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
	// RecoveryPhrase is set only on the first sign-in of an account an admin
	// created, which had no phrase until now. It is not stored anywhere the
	// caller can ask for it again.
	RecoveryPhrase string
}

// GetAuthStatusParams contains parameters for GetAuthStatus.
type GetAuthStatusParams struct {
	// SessionToken is the caller's session token, empty for an anonymous caller.
	SessionToken string
}

// GetAuthStatusResult describes the Quark's setup state and, for a caller
// with a valid session, who that caller is.
type GetAuthStatusResult struct {
	Setup bool
	// Authenticated is true only when SessionToken named a valid session.
	Authenticated bool
	Username      string
	IsAdmin       bool
}

// RecoverParams contains parameters for password recovery.
type RecoverParams struct {
	Username       string
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

// GetAuthStatus reports whether setup is complete and, when the session token
// is valid, the caller's username and admin flag. An invalid or missing token
// is not an error: the caller is simply anonymous.
func GetAuthStatus(ctx context.Context, queries *db.Queries, params GetAuthStatusParams) (GetAuthStatusResult, error) {
	setup, err := IsSetupComplete(ctx, queries)
	if err != nil {
		return GetAuthStatusResult{}, err
	}
	result := GetAuthStatusResult{Setup: setup}
	if params.SessionToken == "" {
		return result, nil
	}
	username, _, err := ValidateSession(ctx, queries, params.SessionToken)
	if err != nil {
		return result, nil
	}
	isAdmin, err := IsAdmin(ctx, queries, username)
	if err != nil {
		return GetAuthStatusResult{}, err
	}
	result.Authenticated = true
	result.Username = username
	result.IsAdmin = isAdmin
	return result, nil
}

// Setup creates the first user and returns a session token + recovery phrase.
// Returns an error if setup has already been completed.
//
// The founding admin gets a home at users/<username> like every other account
// (#1908). An admin bypasses the access table only while they are an admin,
// and demoting one is allowed as long as another is left, so the home is what
// they still have to write to afterwards. A home that cannot be made fails
// setup rather than leaving an account without one.
func Setup(ctx context.Context, params SetupParams) (*SetupResult, error) {
	if err := validateUsername(params.Username); err != nil {
		return nil, err
	}
	if len(params.Password) < 8 {
		return nil, ErrPasswordTooShort
	}
	if params.Database == nil {
		return nil, errors.New("database not initialized")
	}
	queries := params.Database.Queries

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

	var userID int64
	madeDir := ""
	err = inTx(ctx, params.Database, func(q *db.Queries) error {
		user, err := q.CreateUser(ctx, db.CreateUserParams{
			Username:           params.Username,
			PasswordHash:       passwordHash,
			RecoveryPhraseHash: recoveryHash,
		})
		if err != nil {
			return fmt.Errorf("failed to create user: %w", err)
		}
		userID = user.ID

		// First user is automatically the admin.
		if err := q.SetUserAdmin(ctx, db.SetUserAdminParams{
			IsAdmin:  1,
			Username: user.Username,
		}); err != nil {
			return fmt.Errorf("promote first user to admin: %w", err)
		}

		_, dir, err := createHome(ctx, q, params.FilesDir, params.Username, user.ID)
		madeDir = dir
		return err
	})
	if err != nil {
		if madeDir != "" {
			// Best-effort, and only the home this call made: it is new and
			// empty, and the error that got here is the one worth reporting.
			_ = os.Remove(madeDir)
		}
		return nil, err
	}

	token, err := newSession(ctx, queries, userID)
	if err != nil {
		return nil, err
	}

	return &SetupResult{
		SessionToken:   token,
		RecoveryPhrase: recoveryPhrase,
	}, nil
}

// RequestAccount creates a pending account that can sign in once an admin
// approves it, and returns its recovery phrase. It returns
// ErrAccessRequestsOff while requests are off or before setup, and
// ErrInvalidUsername, ErrPasswordTooShort or ErrUsernameTaken for a request
// that cannot be taken. A pending request holds its username until it is
// denied.
func RequestAccount(ctx context.Context, queries *db.Queries, params RequestAccountParams) (RequestAccountResult, error) {
	if !params.RequestsEnabled {
		return RequestAccountResult{}, ErrAccessRequestsOff
	}
	complete, err := IsSetupComplete(ctx, queries)
	if err != nil {
		return RequestAccountResult{}, err
	}
	if !complete {
		return RequestAccountResult{}, ErrAccessRequestsOff
	}
	if err := validateUsername(params.Username); err != nil {
		return RequestAccountResult{}, err
	}
	if len(params.Password) < 8 {
		return RequestAccountResult{}, ErrPasswordTooShort
	}

	passwordHash, err := HashPassword(params.Password)
	if err != nil {
		return RequestAccountResult{}, err
	}
	recoveryPhrase, err := GenerateRecoveryPhrase()
	if err != nil {
		return RequestAccountResult{}, err
	}
	recoveryHash, err := HashPassword(recoveryPhrase)
	if err != nil {
		return RequestAccountResult{}, err
	}
	if _, err := queries.CreatePendingUser(ctx, db.CreatePendingUserParams{
		Username:           params.Username,
		PasswordHash:       passwordHash,
		RecoveryPhraseHash: recoveryHash,
	}); err != nil {
		if sqlutil.IsUniqueConstraintErr(err) {
			return RequestAccountResult{}, ErrUsernameTaken
		}
		return RequestAccountResult{}, fmt.Errorf("create account request: %w", err)
	}
	return RequestAccountResult{RecoveryPhrase: recoveryPhrase}, nil
}

// ApproveRequest makes a pending request an active account, with a home at
// users/<username> that it owns, in one transaction (#1908). A request carries
// no home of its own, and an account with no owner row cannot write anywhere,
// so approving without one produced an account that 403s on every upload.
//
// It returns ErrRequestNotFound when the username names no pending request,
// and ErrFolderExists when a home of that name is already taken — in which
// case the request stays pending rather than becoming an account that cannot
// use its home.
func ApproveRequest(ctx context.Context, params ApproveRequestParams) (ApproveRequestResult, error) {
	if params.Database == nil {
		return ApproveRequestResult{}, errors.New("database not initialized")
	}
	var result ApproveRequestResult
	madeDir := ""
	err := inTx(ctx, params.Database, func(q *db.Queries) error {
		approved, err := q.SetUserStatus(ctx, db.SetUserStatusParams{
			Username:   params.Username,
			FromStatus: StatusPending,
			ToStatus:   StatusActive,
		})
		if err != nil {
			return fmt.Errorf("approve %q: %w", params.Username, err)
		}
		if approved == 0 {
			return ErrRequestNotFound
		}
		user, err := q.GetUserByUsername(ctx, params.Username)
		if err != nil {
			return fmt.Errorf("look up %q: %w", params.Username, err)
		}
		relPath, dir, err := createHome(ctx, q, params.FilesDir, params.Username, user.ID)
		madeDir = dir
		if err != nil {
			return err
		}
		result.FolderPath = relPath
		return nil
	})
	if err != nil {
		if madeDir != "" {
			// Best-effort, and only the home this call made: it is new and
			// empty, and the error that got here is the one worth reporting.
			_ = os.Remove(madeDir)
		}
		return ApproveRequestResult{}, err
	}
	return result, nil
}

// DenyRequest deletes a pending request, which frees its username at once. It
// returns ErrRequestNotFound when the username names no pending request.
func DenyRequest(ctx context.Context, queries *db.Queries, params DenyRequestParams) (DenyRequestResult, error) {
	denied, err := queries.DeletePendingUser(ctx, params.Username)
	if err != nil {
		return DenyRequestResult{}, fmt.Errorf("deny %q: %w", params.Username, err)
	}
	if denied == 0 {
		return DenyRequestResult{}, ErrRequestNotFound
	}
	return DenyRequestResult{}, nil
}

// Login validates credentials and returns a session token. The password is
// checked before the account's status, so ErrAccountPending and
// ErrAccountDisabled reach only someone who knows the password, and a wrong
// password reveals nothing about which usernames exist.
func Login(ctx context.Context, queries *db.Queries, params LoginParams) (*LoginResult, error) {
	user, err := queries.GetUserByUsername(ctx, params.Username)
	if err != nil {
		// Don't leak whether the username exists
		return nil, fmt.Errorf("invalid credentials")
	}

	if !CheckPassword(params.Password, user.PasswordHash) {
		return nil, fmt.Errorf("invalid credentials")
	}
	if err := statusError(user.Status); err != nil {
		return nil, err
	}
	recoveryPhrase, err := firstRecoveryPhrase(ctx, queries, user)
	if err != nil {
		return nil, err
	}

	token, err := newSession(ctx, queries, user.ID)
	if err != nil {
		return nil, err
	}

	return &LoginResult{SessionToken: token, RecoveryPhrase: recoveryPhrase}, nil
}

// CreateUser adds an active account for an admin, with no recovery phrase
// until its first sign-in, and a home at users/<username> that it owns
// (#2016). Homes live under users/ so that a username and a top-level folder
// name are different namespaces: a Quark with a family/ folder can still have
// an account named family. It returns ErrInvalidUsername, ErrPasswordTooShort,
// ErrUsernameTaken, or ErrFolderExists when that home is already taken; a
// refused account leaves no row behind, and no folder except the shared users
// parent.
func CreateUser(ctx context.Context, params CreateUserParams) (CreateUserResult, error) {
	if err := validateUsername(params.Username); err != nil {
		return CreateUserResult{}, err
	}
	if len(params.Password) < 8 {
		return CreateUserResult{}, ErrPasswordTooShort
	}
	if params.Database == nil {
		return CreateUserResult{}, errors.New("database not initialized")
	}
	passwordHash, err := HashPassword(params.Password)
	if err != nil {
		return CreateUserResult{}, err
	}

	var result CreateUserResult
	madeDir := ""
	err = inTx(ctx, params.Database, func(q *db.Queries) error {
		// An empty hash is "no phrase yet": bcrypt never matches it, so recovery
		// fails like a wrong phrase until Login fills it in.
		user, err := q.CreateUser(ctx, db.CreateUserParams{
			Username:     params.Username,
			PasswordHash: passwordHash,
		})
		if sqlutil.IsUniqueConstraintErr(err) {
			return ErrUsernameTaken
		}
		if err != nil {
			return fmt.Errorf("create account: %w", err)
		}
		result.UserID, result.CreatedAt = user.ID, user.CreatedAt

		relPath, dir, err := createHome(ctx, q, params.FilesDir, params.Username, user.ID)
		madeDir = dir
		if err != nil {
			return err
		}
		result.FolderPath = relPath
		return nil
	})
	if err != nil {
		if madeDir != "" {
			// Best-effort, and only the account's own home: the users parent
			// may hold other people's. The home is new and empty, and the error
			// that got here is the one worth reporting.
			_ = os.Remove(madeDir)
		}
		return CreateUserResult{}, err
	}
	return result, nil
}

// RepairHomesParams is the Quark whose accounts are repaired.
type RepairHomesParams struct {
	Database *db.DatabaseSqlc
	// FilesDir is the internal device's files directory, where homes live.
	FilesDir string
}

// RepairHomesResult names the accounts that were given their home.
type RepairHomesResult struct {
	Repaired []string
}

// RepairHomes gives every active account with no owner row on users/<username>
// one, and makes the directory when it is missing (#1908).
//
// Approval used to create neither the directory nor the grant, and an account
// created before homes were always made has neither, so those accounts are
// refused every write. This runs at startup rather than as a migration because
// a migration is SQL and cannot make a directory.
//
// It keys on the missing grant, never on the missing directory: a hand-made
// users/<username> with no row behaves exactly like no home at all, so such an
// account is repaired by granting it what is already there. Running it again on
// a repaired Quark does nothing.
func RepairHomes(ctx context.Context, params RepairHomesParams) (RepairHomesResult, error) {
	var result RepairHomesResult
	if params.Database == nil {
		return result, errors.New("database not initialized")
	}
	if params.FilesDir == "" {
		return result, errors.New("files directory not set")
	}
	accounts, err := params.Database.Queries.ListAccountsMissingHome(ctx)
	if err != nil {
		return result, fmt.Errorf("list the accounts with no home: %w", err)
	}
	for _, account := range accounts {
		// An account made before the username rule may hold a name that is not
		// one path segment (#1908). It keeps no home rather than being given a
		// directory somewhere else in the tree.
		if err := validateUsername(account.Username); err != nil {
			slog.Warn("no home repaired: the username is not a folder name", "username", account.Username)
			continue
		}
		// MkdirAll, not Mkdir: the repair ends with the directory there, so one
		// that already exists is adopted rather than refused.
		if err := os.MkdirAll(filepath.Join(params.FilesDir, UsersDirName, account.Username), 0o755); err != nil {
			return result, fmt.Errorf("create the home of %q: %w", account.Username, err)
		}
		if err := grantHome(ctx, params.Database.Queries, account.Username, account.ID); err != nil {
			return result, err
		}
		result.Repaired = append(result.Repaired, account.Username)
	}
	return result, nil
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
	if err := statusError(user.Status); err != nil {
		return "", 0, err
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
		return nil, ErrPasswordTooShort
	}

	// An unknown username gets the same error as a wrong phrase, so the
	// endpoint does not reveal which usernames exist.
	user, err := queries.GetUserByUsername(ctx, params.Username)
	if err != nil {
		return nil, fmt.Errorf("invalid recovery phrase")
	}

	normalized := NormalizeRecoveryPhrase(params.RecoveryPhrase)
	if !CheckPassword(normalized, user.RecoveryPhraseHash) {
		return nil, fmt.Errorf("invalid recovery phrase")
	}
	// After the phrase, for the same reason Login checks status after the
	// password.
	if err := statusError(user.Status); err != nil {
		return nil, err
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

// IsActive reports whether the account with the given id exists and may sign
// in. A missing account is not an error; it is simply not active.
func IsActive(ctx context.Context, queries *db.Queries, userID int64) (bool, error) {
	user, err := queries.GetUserByID(ctx, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("look up account: %w", err)
	}
	return user.Status == StatusActive, nil
}

// IsActiveAs reports whether the account with the given id exists, may sign
// in, and is still an admin exactly when isAdmin says so. An open event stream
// asks this to find out that its account was turned off, deleted, promoted or
// demoted since it connected. A missing account is not an error.
func IsActiveAs(ctx context.Context, queries *db.Queries, userID int64, isAdmin bool) (bool, error) {
	user, err := queries.GetUserByID(ctx, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("look up account: %w", err)
	}
	return user.Status == StatusActive && (user.IsAdmin != 0) == isAdmin, nil
}

// DisableUser turns an account off (#1909): it can no longer sign in, and every
// session it holds ends in the same transaction. It keeps everything it owns,
// so EnableUser restores it as it was. It returns ErrSelfAction for the acting
// admin's own account, ErrUserNotFound unless the account is active, and
// ErrLastAdmin for the only active admin.
func DisableUser(ctx context.Context, params DisableUserParams) (DisableUserResult, error) {
	if params.Database == nil {
		return DisableUserResult{}, errors.New("database not initialized")
	}
	err := inTx(ctx, params.Database, func(q *db.Queries) error {
		target, err := q.GetUserByUsername(ctx, params.Username)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrUserNotFound
		}
		if err != nil {
			return fmt.Errorf("look up %q: %w", params.Username, err)
		}
		if target.ID == params.ActorUserID {
			return ErrSelfAction
		}
		if err := ensureAnotherActiveAdmin(ctx, q, target); err != nil {
			return err
		}
		disabled, err := q.SetUserStatus(ctx, db.SetUserStatusParams{
			Username:   params.Username,
			FromStatus: StatusActive,
			ToStatus:   StatusDisabled,
		})
		if err != nil {
			return fmt.Errorf("disable %q: %w", params.Username, err)
		}
		if disabled == 0 {
			return ErrUserNotFound
		}
		if err := q.DeleteUserSessions(ctx, target.ID); err != nil {
			return fmt.Errorf("end sessions of %q: %w", params.Username, err)
		}
		return nil
	})
	return DisableUserResult{}, err
}

// EnableUser turns a disabled account back on. It returns ErrUserNotFound
// unless the account is disabled.
func EnableUser(ctx context.Context, queries *db.Queries, params EnableUserParams) (EnableUserResult, error) {
	enabled, err := queries.SetUserStatus(ctx, db.SetUserStatusParams{
		Username:   params.Username,
		FromStatus: StatusDisabled,
		ToStatus:   StatusActive,
	})
	if err != nil {
		return EnableUserResult{}, fmt.Errorf("enable %q: %w", params.Username, err)
	}
	if enabled == 0 {
		return EnableUserResult{}, ErrUserNotFound
	}
	return EnableUserResult{}, nil
}

// DeleteUser deletes an account without orphaning its files, in one
// transaction: every path it owned is handed to an heir, then its sessions and
// row go, and ON DELETE CASCADE takes its remaining access rows and group
// memberships. Files stay where they are.
//
// An admin's delete (ActorUserID set) hands the paths to that admin and refuses
// the admin's own account with ErrSelfAction. A self-service delete hands them
// to the longest-standing active admin. Deleting the only active admin returns
// ErrLastAdmin while any other active or disabled account exists; when only
// pending requests are left, they are deleted too and the Quark returns to
// setup. A username with no account returns ErrUserNotFound.
func DeleteUser(ctx context.Context, params DeleteUserParams) (DeleteUserResult, error) {
	if params.Database == nil {
		return DeleteUserResult{}, errors.New("database not initialized")
	}
	var result DeleteUserResult
	err := inTx(ctx, params.Database, func(q *db.Queries) error {
		target, err := q.GetUserByUsername(ctx, params.Username)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrUserNotFound
		}
		if err != nil {
			return fmt.Errorf("look up %q: %w", params.Username, err)
		}
		if target.ID == params.ActorUserID {
			return ErrSelfAction
		}

		if errors.Is(ensureAnotherActiveAdmin(ctx, q, target), ErrLastAdmin) {
			others, err := q.CountOtherAccounts(ctx, target.ID)
			if err != nil {
				return fmt.Errorf("count accounts: %w", err)
			}
			if others > 0 {
				return ErrLastAdmin
			}
			if err := q.DeletePendingUsers(ctx); err != nil {
				return fmt.Errorf("delete account requests: %w", err)
			}
		}

		heir := params.ActorUserID
		if heir == 0 {
			oldest, err := q.GetOldestActiveAdmin(ctx, target.ID)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return fmt.Errorf("find an heir: %w", err)
			}
			heir = oldest.ID
		}
		if heir != 0 {
			reassigned, err := q.ReassignOwnerRows(ctx, db.ReassignOwnerRowsParams{
				ToUserID:   heir,
				FromUserID: sql.NullInt64{Int64: target.ID, Valid: true},
			})
			if err != nil {
				return fmt.Errorf("hand over owned paths: %w", err)
			}
			result.HeirUserID, result.OwnerRowsReassigned = heir, reassigned
		}

		if err := q.DeleteUserSessions(ctx, target.ID); err != nil {
			return fmt.Errorf("end sessions: %w", err)
		}
		if err := q.DeleteUser(ctx, target.ID); err != nil {
			return fmt.Errorf("delete %q: %w", params.Username, err)
		}
		remaining, err := q.CountUsers(ctx)
		if err != nil {
			return fmt.Errorf("count accounts: %w", err)
		}
		result.SetupReset = remaining == 0
		return nil
	})
	if err != nil {
		return DeleteUserResult{}, err
	}
	return result, nil
}

// PromoteToAdmin grants admin to the given username. Only an active account
// can be promoted; any other username returns ErrUserNotFound.
func PromoteToAdmin(ctx context.Context, queries *db.Queries, username string) error {
	if _, err := queries.PromoteToAdmin(ctx, username); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrUserNotFound
		}
		return fmt.Errorf("promote %q to admin: %w", username, err)
	}
	return nil
}

// DemoteFromAdmin removes admin from the given username. It returns
// ErrLastAdmin when the account is the only active admin, and ErrUserNotFound
// for a username with no account.
func DemoteFromAdmin(ctx context.Context, queries *db.Queries, username string) error {
	target, err := queries.GetUserByUsername(ctx, username)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrUserNotFound
	}
	if err != nil {
		return fmt.Errorf("look up %q: %w", username, err)
	}
	if err := ensureAnotherActiveAdmin(ctx, queries, target); err != nil {
		return err
	}
	if _, err := queries.DemoteFromAdmin(ctx, username); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrUserNotFound
		}
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
// Order is deliberate. The account goes first, through DeleteUser, because it
// is the one aspect that can be refused: the only active admin cannot delete
// themselves while other accounts remain (#1909), and a refusal must leave
// everything, the caller's sessions included, as it was. DeleteUser deletes the
// account's sessions in the same transaction as its row, so no client keeps
// operating as a deleted account.
//
// Sessions go next so no client keeps operating against a half-erased
// appliance. The account aspect is opt-in and the other three do not touch the
// users table, so a factory reset without it would otherwise leave every
// session live against the wiped appliance.
//
// Both happen before the destructive filesystem work: a caller who asked for
// their account to be deleted must not be left with it alive because a later
// aspect failed. The databases go last because a database reset
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

	if params.DeleteAccount {
		// DeleteUser hands the account's owned paths to the oldest active admin
		// and deletes its sessions and row in one transaction, or refuses with
		// ErrLastAdmin before anything is touched. An account that is already
		// gone is the state asked for, so a repeat call still succeeds.
		if _, err := DeleteUser(ctx, DeleteUserParams{
			Database: params.Database,
			Username: params.Username,
		}); err != nil && !errors.Is(err, ErrUserNotFound) {
			return result, err
		}
		result.AccountDeleted = true
	}

	if err := RevokeAllSessions(ctx, params.Queries, params.UserID); err != nil {
		return result, err
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
