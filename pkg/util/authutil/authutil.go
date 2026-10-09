// Package authutil handles authentication: hashing the auth and recovery keys
// clients derive, first-boot setup, login, session issue and validation,
// account status, and admin role management. A legacy account's password and
// recovery phrase are taken once each, to move it to keys; anywhere else a raw
// one is refused with ErrAppTooOld (#2430).
//
// A key is 32 bytes a client derived with Argon2id, so it is stored as a
// SHA-256 digest, as a session token is, and checked in constant time
// (#2765). bcrypt is only ever verified, never written: for the password and
// recovery phrase hashes of an account that has not moved to keys, and for a
// key hash written before keys took SHA-256, which the first correct auth key
// rewrites.
package authutil

import (
	"context"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/bcrypt"
)

const sessionTokenSize = 32 // bytes → 64 hex chars

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

// GroupsDirName is the directory under the files directory that holds every
// group's folder, groups/<name>, beside users/ so a group and an account may
// share a name (#2016). grouputil makes the folders; it lives here with
// UsersDirName because accessutil reads both and may import only authutil.
const GroupsDirName = "groups"

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
	// ErrInvalidRecoveryPhrase refuses a recovery phrase or key that isn't the
	// named account's, or a username that doesn't exist. It names the phrase
	// because that is what the person typed.
	ErrInvalidRecoveryPhrase = errors.New("invalid recovery phrase")
	// ErrSelfAction refuses an admin action aimed at the admin's own account.
	ErrSelfAction = errors.New("use Settings to change your own account")
	// ErrIncorrectPassword refuses a destructive action whose auth key is not
	// the caller's (#2346). It names the password because that is what the
	// person typed.
	ErrIncorrectPassword = errors.New("incorrect password")
	// ErrInvalidAuthKey refuses an auth key that is missing or is not the
	// standard base64 of exactly 32 bytes (#2430).
	ErrInvalidAuthKey = errors.New("authKey must be the base64 of 32 bytes")
	// ErrInvalidRecoveryKey refuses a recovery key that is missing or is not
	// the standard base64 of exactly 32 bytes (#2430).
	ErrInvalidRecoveryKey = errors.New("a recovery key must be the base64 of 32 bytes")
	// ErrRecoverySecretRequired refuses a recovery that carries neither or both
	// of a recovery phrase and a recovery key.
	ErrRecoverySecretRequired = errors.New("send a recoveryPhrase or a recoveryKey, not both")
	// ErrNoAuthSalt refuses a recovery key for an account that has no auth salt
	// to derive it with, one that has never signed in with an auth key.
	ErrNoAuthSalt = errors.New("this account has no auth key yet: sign in with an authKey first")
)

// ErrAppTooOld refuses a request shaped the way only an app from before auth
// keys sends it (#2430): a raw password or recovery phrase with no key beside
// it to move the account to. It is a 426
// HttpError, so a handler that passes it on answers 426 whatever status it
// chose. Released apps show a 426's error text as it is, so this is the
// sentence an old app's user reads.
var ErrAppTooOld error = serverutil.NewHttpError(http.StatusUpgradeRequired,
	"This version of the app is too old for this Quark. Update the app to continue.")

// ErrUnavailable reports a credential the database could not be asked about,
// which says nothing about whether it is right (#2858). A credential with no
// row behind it is not this: that one is wrong. It is a 503 HttpError, so a
// handler that passes it on answers 503 whatever status it chose, and an app
// keeps the session a 401 would have made it drop. The database's own error
// is logged where it happened and is not part of this one.
var ErrUnavailable error = serverutil.NewHttpError(http.StatusServiceUnavailable, "service unavailable")

// RefuseRawSecrets returns ErrAppTooOld when any of secrets is set. Handlers
// pass it the legacy fields a body can carry only from an old app (password at
// setup and account creation, newPassword at recovery) before anything is
// looked up or hashed.
func RefuseRawSecrets(secrets ...string) error {
	for _, secret := range secrets {
		if secret != "" {
			return ErrAppTooOld
		}
	}
	return nil
}

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
	// UserID is the deleted account's id.
	UserID int64
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
	// AuthKey is the key the admin's client derived from the password and the
	// account's salt (#2430).
	AuthKey string
	// SaltSecret returns the install's salt secret, to store the salt the key
	// was derived with.
	SaltSecret func() ([]byte, error)
	// Files is the internal drive's files namespace, where the account's home
	// is made.
	Files vfs.VFS
}

// CreateUserResult is the account that was added.
type CreateUserResult struct {
	UserID    int64
	CreatedAt time.Time
	// FolderPath is the home's path relative to the files root — users/<username>.
	FolderPath string
}

// RequestAccountParams asks for an account from the sign-in page (#1908).
type RequestAccountParams struct {
	Username string
	// AuthKey is the key the client derived from the password and the
	// account's salt (#2430).
	AuthKey string
	// SaltSecret returns the install's salt secret, to store the salt the key
	// was derived with.
	SaltSecret func() ([]byte, error)
	// RecoveryKey is the key the client derived from a recovery phrase it
	// generated (#2430). Without it the account has no recovery credential
	// until its client gives it one with SetRecoveryKey.
	RecoveryKey string
	// RequestsEnabled is the admin's access-request setting.
	RequestsEnabled bool
}

// RequestAccountResult is empty: the client made the recovery phrase, so the
// Quark has nothing to hand back (#2430).
type RequestAccountResult struct{}

// ApproveRequestParams names the pending request an admin approves.
type ApproveRequestParams struct {
	Database *db.DatabaseSqlc
	Username string
	// Files is the internal drive's files namespace, where the approved
	// account's home is made.
	Files vfs.VFS
}

// ApproveRequestResult is the approved account's home.
type ApproveRequestResult struct {
	// FolderPath is the home's path relative to the files root — users/<username>.
	FolderPath string
}

// DenyRequestParams names the pending request an admin denies.
type DenyRequestParams struct {
	Username string
}

// DenyRequestResult is empty; a denial has nothing to report.
type DenyRequestResult struct{}

// InternalFiles returns the internal drive's files namespace from registry,
// where every home and group folder lives (accessutil.IsHomeRoot,
// IsGroupRoot). It is an error when there is none.
func InternalFiles(registry vfs.Registry) (vfs.VFS, error) {
	if registry != nil {
		if files, ok := registry.Get(vfs.FilesNamespace("")); ok {
			return files, nil
		}
	}
	return nil, errors.New("files namespace not registered")
}

// MakeFolder makes the folder at relPath in files unless one is already
// there, which is adopted, and reports whether it made it. Something other
// than a folder at relPath is an error rather than passing as one. Its
// parents are made as needed: users/ and groups/ are shared, so them already
// existing is not a conflict.
func MakeFolder(ctx context.Context, files vfs.VFS, relPath string) (made bool, err error) {
	if files == nil {
		return false, errors.New("files namespace not set")
	}
	info, err := files.Stat(ctx, relPath)
	switch {
	case err == nil && info.IsDir:
		return false, nil
	case err == nil:
		return false, fmt.Errorf("%s is not a folder", relPath)
	case !errors.Is(err, vfs.ErrNotFound):
		return false, err
	}
	if err := files.MkdirAll(ctx, relPath); err != nil {
		return false, err
	}
	return true, nil
}

// RemoveMadeFolder removes madeDir, a folder MakeFolder made for a creation
// that then failed. It is best-effort and removes only an empty directory, so
// whatever landed in it meanwhile survives; the error that got the caller
// here is the one worth reporting. It runs even when ctx was canceled, since a
// canceled request is one of the failures it cleans up after. An empty
// madeDir, an adopted folder, is left alone.
func RemoveMadeFolder(ctx context.Context, files vfs.VFS, madeDir string) {
	if madeDir == "" {
		return
	}
	_ = files.Delete(context.WithoutCancel(ctx), madeDir, vfs.DeleteOptions{})
}

// SetupParams contains parameters for first-boot user setup.
type SetupParams struct {
	Database *db.DatabaseSqlc
	Username string
	// AuthKey is the key the client derived from the password and the
	// account's salt (#2430).
	AuthKey string
	// SaltSecret returns the install's salt secret, to store the salt the key
	// was derived with.
	SaltSecret func() ([]byte, error)
	// RecoveryKey is the key the client derived from a recovery phrase it
	// generated (#2430). Without it the account has no recovery credential
	// until its client gives it one with SetRecoveryKey.
	RecoveryKey string
	// Files is the internal drive's files namespace, where the founding
	// admin's home is made.
	Files vfs.VFS
}

// SetupResult contains the result of first-boot setup.
type SetupResult struct {
	SessionToken string
}

// LoginParams contains parameters for login: the username and the auth key
// the client derived from the password (#2430). Password, sent beside AuthKey,
// is the one-time upgrade of an account that has no auth key yet; alone it is
// an old app's sign-in and is refused with ErrAppTooOld.
type LoginParams struct {
	Username string
	Password string
	AuthKey  string
	// SaltSecret returns the install's salt secret. It is called only for an
	// upgrade, to store the salt the key was derived with.
	SaltSecret func() ([]byte, error)
	// Guard locks out an address or account after repeated failures (#1861);
	// nil checks nothing.
	Guard *ratelimitutil.LoginGuard
	// ClientIP is the address the attempt came from, which Guard keys on.
	ClientIP string
}

// TooManyAttemptsError refuses a sign-in while Guard has its address or
// account locked out, before the password is checked. It reads the same
// whether or not the username exists.
type TooManyAttemptsError struct {
	// RetryAfter is how long until the lockout lifts.
	RetryAfter time.Duration
}

func (e *TooManyAttemptsError) Error() string {
	return "too many failed sign-in attempts, try again later"
}

// GetSaltParams names the account whose key-derivation salt is asked for.
type GetSaltParams struct {
	Username string
	// SaltSecret returns the install's salt secret.
	SaltSecret func() ([]byte, error)
}

// GetSaltResult is the salt a client derives its auth key with.
type GetSaltResult struct {
	// Salt is the standard base64 of 16 bytes.
	Salt string
	// Legacy is true for an account that has no auth key yet, which the client
	// upgrades by signing in once with the password beside the key (#2430).
	Legacy bool
	// LegacyRecovery is true for an account that has no recovery key, whose
	// client gives it one at sign-in, or recovers it once with the raw phrase
	// and a new phrase's key.
	LegacyRecovery bool
}

// DeriveKeyParams is a secret and the salt its key is derived with.
type DeriveKeyParams struct {
	// Secret is the password, or with Recovery the recovery phrase.
	Secret string
	// Salt is the account's salt as GET /auth/salt returns it: the standard
	// base64 of 16 bytes.
	Salt string
	// Recovery derives the recovery key of a phrase rather than the auth key
	// of a password.
	Recovery bool
}

// DeriveKeyResult is a derived key.
type DeriveKeyResult struct {
	// Key is the standard base64 of 32 bytes: authKey, or recoveryKey, as a
	// request carries it.
	Key string
}

// DeriveKey derives the key a client sends in a password's or a recovery
// phrase's place (#2430), for a client that has no app to do it (#2713):
//
//	master = Argon2id13(secret, salt, t=3, m=64 MiB, p=1), 32 bytes
//	key    = HKDF-SHA256(master, no salt, info "auth" or "recovery-auth"), 32 bytes
//
// A phrase is lowercased and trimmed first. This is ChatCrypto.deriveAuthKeys
// and deriveRecoveryKeys in the app, and TestDeriveKey_MatchesTheApp pins it
// to the app's vectors. The Quark never calls it on a request: it is handed
// keys, not secrets, and each call costs 64 MiB.
func DeriveKey(params DeriveKeyParams) (DeriveKeyResult, error) {
	salt, err := base64.StdEncoding.DecodeString(params.Salt)
	if err != nil || len(salt) != authSaltSize {
		return DeriveKeyResult{}, fmt.Errorf("salt %q is not the base64 of %d bytes", params.Salt, authSaltSize)
	}
	secret, info := params.Secret, "auth"
	if params.Recovery {
		secret, info = normalizeRecoveryPhrase(params.Secret), "recovery-auth"
	}
	master := argon2.IDKey([]byte(secret), salt, 3, 64*1024, 1, authKeySize)
	key, err := hkdf.Key(sha256.New, master, nil, info, authKeySize)
	if err != nil {
		return DeriveKeyResult{}, fmt.Errorf("derive the key: %w", err)
	}
	return DeriveKeyResult{Key: base64.StdEncoding.EncodeToString(key)}, nil
}

// LoginResult contains the result of a successful login.
type LoginResult struct {
	SessionToken string
	// LegacyRecovery is true for an account that has no recovery key yet, such
	// as one an admin created, so the client gives it one with SetRecoveryKey
	// (#2430).
	LegacyRecovery bool
}

// CheckRecoveryParams names an account and the one recovery secret it gave:
// the raw phrase of an account that has no recovery key yet, or the key the
// client derived from the phrase and the auth salt (#2430).
type CheckRecoveryParams struct {
	Username       string
	RecoveryPhrase string
	RecoveryKey    string
}

// CheckRecoveryResult is the account the secret recovers.
type CheckRecoveryResult struct {
	UserID int64
}

// SetRecoveryKeyParams gives the signed-in account a recovery key.
type SetRecoveryKeyParams struct {
	UserID int64
	// RecoveryKey is the standard base64 of the 32-byte key the client derived
	// from the phrase it generated and the account's auth salt.
	RecoveryKey string
	// AfterSet, when set, runs in the transaction that stores the key, with
	// that transaction's queries and the account's id. An error rolls the key
	// back. Chat uses it to store the identity re-wrapped under the new phrase.
	AfterSet func(queries *db.Queries, userID int64) error
}

// SetRecoveryKeyResult is empty; a stored key has nothing to report.
type SetRecoveryKeyResult struct{}

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
	// UserID is the caller's account id, zero without a valid session.
	UserID  int64
	IsAdmin bool
}

// RecoverParams contains parameters for password recovery. Exactly one of
// RecoveryPhrase and RecoveryKey is set.
type RecoverParams struct {
	Username string
	// RecoveryPhrase is the raw phrase of an account that has no recovery key
	// yet (#2430). It is taken only beside NewAuthKey and NewRecoveryKey, so
	// the recovery moves the account to keys; without them it is an old app's
	// recovery and is refused with ErrAppTooOld.
	RecoveryPhrase string
	RecoveryKey    string
	// NewAuthKey is the key the client derived from the new password (#2430).
	NewAuthKey string
	// NewRecoveryKey, when set, replaces the recovery credential in the same
	// transaction: a legacy phrase recovery hands the account the key of a
	// phrase its client just generated (#2430).
	NewRecoveryKey string
	// SaltSecret returns the install's salt secret, for an account that has no
	// stored salt.
	SaltSecret func() ([]byte, error)
	// AfterReset, when set, runs in the transaction that resets the password,
	// with that transaction's queries and the account's id. An error rolls the
	// reset back. Chat uses it to store keys re-wrapped under the new password
	// (#2416), which authutil knows nothing about.
	AfterReset func(queries *db.Queries, userID int64) error
}

// SessionInfo is a safe, token-free representation of an active session
// returned to the caller. The ID is the hex-encoded SHA-256 of the raw token
// so clients can reference a session for revocation without exposing the token.
type SessionInfo struct {
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"createdAt"`
	ExpiresAt time.Time `json:"expiresAt"`
	// LastUsedAt is when the session last renewed itself; renewal is
	// debounced, so it can trail the newest request.
	LastUsedAt time.Time `json:"lastUsedAt"`
	// Current marks the session the request was authenticated with.
	Current bool `json:"current"`
}

// SessionID returns the id a session token is listed and revoked under: the
// digest it is stored as.
func SessionID(token string) string {
	return hashToken(token)
}

// HashKey returns the hash an auth key or a recovery key is stored as:
// "sha256:" and the hex SHA-256 of the key as the client sent it (#2765). The
// key is 32 random-looking bytes that Argon2id already stands in front of, so
// a slow hash adds nothing, and Basic auth pays for the hash on every request.
//
// It refuses anything not shaped like a key, the standard base64 of exactly
// 32 bytes, so a secret a person chose can never be stored under the fast
// hash.
func HashKey(key string) (string, error) {
	if err := validateKey(key, errNotAKey); err != nil {
		return "", err
	}
	return keyHashPrefix + hashToken(key), nil
}

// CheckPassword verifies a secret against the hash stored for it. A hash from
// HashKey is compared in constant time. Anything else is taken as bcrypt: the
// password or recovery phrase hash of an account that has not moved to keys,
// or a key hash from before HashKey (#2765). An empty hash, which is how an
// unset credential is stored, matches nothing.
func CheckPassword(secret, hash string) bool {
	if strings.HasPrefix(hash, keyHashPrefix) {
		return subtle.ConstantTimeCompare([]byte(keyHashPrefix+hashToken(secret)), []byte(hash)) == 1
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(secret)) == nil
}

// VerifyPasswordParams names the signed-in account and the auth key it gave
// in the password field the endpoints have always read (#2430).
type VerifyPasswordParams struct {
	Queries  *db.Queries
	Username string
	Password string
}

// VerifyPasswordResult is empty; a correct password has nothing to report.
type VerifyPasswordResult struct{}

// VerifyPassword checks that Password is the auth key of Username, so a
// session on its own is not enough to delete an account or reset the Quark
// (#2346). It returns ErrAppTooOld for a password not shaped like an auth key,
// which is a raw one from an old app (#2430), ErrIncorrectPassword for a
// wrong or empty key, ErrUserNotFound when no account has the username, and any other
// error for a failed lookup.
func VerifyPassword(ctx context.Context, params VerifyPasswordParams) (VerifyPasswordResult, error) {
	if isRawSecret(params.Password) {
		return VerifyPasswordResult{}, ErrAppTooOld
	}
	user, err := params.Queries.GetUserByUsername(ctx, params.Username)
	if errors.Is(err, sql.ErrNoRows) {
		return VerifyPasswordResult{}, ErrUserNotFound
	}
	if err != nil {
		return VerifyPasswordResult{}, fmt.Errorf("look up the account: %w", err)
	}
	if !checkAuthKey(ctx, params.Queries, user, params.Password) {
		return VerifyPasswordResult{}, ErrIncorrectPassword
	}
	return VerifyPasswordResult{}, nil
}

// GenerateSessionToken returns a cryptographically random hex session token.
func GenerateSessionToken() (string, error) {
	b := make([]byte, sessionTokenSize)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("failed to generate session token: %w", err)
	}
	return hex.EncodeToString(b), nil
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
// is not an error: the caller is simply anonymous. A token the database could
// not be asked about is ErrUnavailable, not an anonymous caller.
func GetAuthStatus(ctx context.Context, queries *db.Queries, params GetAuthStatusParams) (GetAuthStatusResult, error) {
	setup, err := IsSetupComplete(ctx, queries)
	if err != nil {
		return GetAuthStatusResult{}, err
	}
	result := GetAuthStatusResult{Setup: setup}
	if params.SessionToken == "" {
		return result, nil
	}
	username, userID, err := ValidateSession(ctx, queries, params.SessionToken)
	if errors.Is(err, ErrUnavailable) {
		return GetAuthStatusResult{}, err
	}
	if err != nil {
		return result, nil
	}
	isAdmin, err := IsAdmin(ctx, queries, username)
	if err != nil {
		return GetAuthStatusResult{}, err
	}
	result.Authenticated = true
	result.Username = username
	result.UserID = userID
	result.IsAdmin = isAdmin
	return result, nil
}

// Setup creates the first user and returns a session token. Returns an error
// if setup has already been completed.
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

	authKeyHash, authSalt, err := newCredentials(params.Username, params.AuthKey, params.SaltSecret)
	if err != nil {
		return nil, err
	}
	recoveryKeyHash, err := recoveryKeyHashFor(params.RecoveryKey)
	if err != nil {
		return nil, err
	}

	var userID int64
	madeDir := ""
	err = inTx(ctx, params.Database, func(q *db.Queries) error {
		user, err := q.CreateUser(ctx, db.CreateUserParams{
			Username:        params.Username,
			AuthKeyHash:     authKeyHash,
			AuthSalt:        authSalt,
			RecoveryKeyHash: recoveryKeyHash,
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

		_, dir, err := createHome(ctx, q, params.Files, params.Username, user.ID)
		madeDir = dir
		return err
	})
	if err != nil {
		RemoveMadeFolder(ctx, params.Files, madeDir)
		return nil, err
	}

	token, err := newSession(ctx, queries, userID)
	if err != nil {
		return nil, err
	}

	return &SetupResult{SessionToken: token}, nil
}

// RequestAccount creates a pending account that can sign in once an admin
// approves it. It returns ErrAccessRequestsOff while requests are off or
// before setup, and ErrInvalidUsername, ErrInvalidAuthKey,
// ErrInvalidRecoveryKey or ErrUsernameTaken for a request that cannot be
// taken. A pending request holds its username until it is denied.
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
	authKeyHash, authSalt, err := newCredentials(params.Username, params.AuthKey, params.SaltSecret)
	if err != nil {
		return RequestAccountResult{}, err
	}
	recoveryKeyHash, err := recoveryKeyHashFor(params.RecoveryKey)
	if err != nil {
		return RequestAccountResult{}, err
	}
	if _, err := queries.CreatePendingUser(ctx, db.CreatePendingUserParams{
		Username:        params.Username,
		AuthKeyHash:     authKeyHash,
		AuthSalt:        authSalt,
		RecoveryKeyHash: recoveryKeyHash,
	}); err != nil {
		if sqlutil.IsUniqueConstraintErr(err) {
			return RequestAccountResult{}, ErrUsernameTaken
		}
		return RequestAccountResult{}, fmt.Errorf("create account request: %w", err)
	}
	return RequestAccountResult{}, nil
}

// ApproveRequest makes a pending request an active account, with a home at
// users/<username> that it owns, in one transaction (#1908). A request carries
// no home of its own, and an account with no owner row cannot write anywhere,
// so approving without one produced an account that 403s on every upload.
//
// It returns ErrRequestNotFound when the username names no pending request. A
// folder already at users/<username> becomes the account's home.
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
		relPath, dir, err := createHome(ctx, q, params.Files, params.Username, user.ID)
		madeDir = dir
		if err != nil {
			return err
		}
		result.FolderPath = relPath
		return nil
	})
	if err != nil {
		RemoveMadeFolder(ctx, params.Files, madeDir)
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

// GetSalt returns the salt a client derives Username's auth key with (#2430).
// An account that has a stored salt gets it. Any other username, whether it
// names a legacy account or none, gets the install's deterministic salt for
// that name, so the answer does not say whether the account exists. The
// deterministic salt is computed on every path so they take the same work.
// Legacy and LegacyRecovery say the account has no auth key or no recovery key
// yet, which its client moves it to (#2430); an unknown username reads false
// for both, like an account that has moved to keys.
func GetSalt(ctx context.Context, queries *db.Queries, params GetSaltParams) (GetSaltResult, error) {
	salt, err := deterministicSalt(params.SaltSecret, params.Username)
	if err != nil {
		return GetSaltResult{}, err
	}
	result := GetSaltResult{Salt: salt}
	user, err := queries.GetUserByUsername(ctx, params.Username)
	if errors.Is(err, sql.ErrNoRows) {
		return result, nil
	}
	if err != nil {
		return GetSaltResult{}, fmt.Errorf("look up the account: %w", err)
	}
	if user.AuthSalt != "" {
		result.Salt = user.AuthSalt
	}
	result.Legacy = user.AuthKeyHash == ""
	result.LegacyRecovery = user.RecoveryKeyHash == ""
	return result, nil
}

// Login validates credentials and returns a session token. The credential is
// checked before the account's status, so ErrAccountPending and
// ErrAccountDisabled reach only someone who knows the password, and a wrong
// one reveals nothing about which usernames exist.
//
// An account with an auth key is checked by it, and a password sent beside it
// is ignored. An account with none is checked by the password sent beside the
// key, and the sign-in upgrades it (#2430): the key, its salt and the cleared
// password hash land in one write, so the password stops signing in and is
// never taken again. A failed upgrade refuses the sign-in rather than leave
// the account on its password. A password with no key is ErrAppTooOld.
//
// With a Guard, a locked-out attempt gets *TooManyAttemptsError without its
// credential being checked, and every wrong username or credential is counted
// toward a lockout and logged with its address. An account lookup the
// database could not answer is ErrUnavailable and is not counted.
func Login(ctx context.Context, queries *db.Queries, params LoginParams) (*LoginResult, error) {
	if params.AuthKey == "" {
		if err := RefuseRawSecrets(params.Password); err != nil {
			return nil, err
		}
	}
	if err := validateAuthKey(params.AuthKey); err != nil {
		return nil, err
	}
	attempt := ratelimitutil.LoginAttempt{Account: params.Username, IP: params.ClientIP}
	user, err := guardedAccount(ctx, queries, params.Guard, attempt, params.AuthKey, params.Password)
	if err != nil {
		return nil, err
	}
	// An account with no auth key got here on its password: this is the
	// sign-in that upgrades it.
	if user.AuthKeyHash == "" {
		if err := upgradeToAuthKey(ctx, queries, user, params.AuthKey, params.SaltSecret); err != nil {
			return nil, err
		}
	}

	token, err := newSession(ctx, queries, user.ID)
	if err != nil {
		return nil, err
	}
	params.Guard.RecordSuccess(attempt)

	return &LoginResult{
		SessionToken:   token,
		LegacyRecovery: user.RecoveryKeyHash == "",
	}, nil
}

// CreateUser adds an active account for an admin, with no recovery
// credential until its first sign-in, when its client gives it a recovery key
// (#2430), and a home at users/<username> that it owns (#2016). Homes live under users/ so that a username and a top-level folder
// name are different namespaces: a Quark with a family/ folder can still have
// an account named family. It returns ErrInvalidUsername, ErrInvalidAuthKey
// or ErrUsernameTaken; a folder already at users/<username> becomes the
// account's home. A refused account leaves no row behind, and no folder
// except the shared users parent.
func CreateUser(ctx context.Context, params CreateUserParams) (CreateUserResult, error) {
	if err := validateUsername(params.Username); err != nil {
		return CreateUserResult{}, err
	}
	if params.Database == nil {
		return CreateUserResult{}, errors.New("database not initialized")
	}
	authKeyHash, authSalt, err := newCredentials(params.Username, params.AuthKey, params.SaltSecret)
	if err != nil {
		return CreateUserResult{}, err
	}

	var result CreateUserResult
	madeDir := ""
	err = inTx(ctx, params.Database, func(q *db.Queries) error {
		// An empty recovery key hash is "none yet": nothing matches it, so
		// recovery fails like a wrong phrase until the client sets one.
		user, err := q.CreateUser(ctx, db.CreateUserParams{
			Username:    params.Username,
			AuthKeyHash: authKeyHash,
			AuthSalt:    authSalt,
		})
		if sqlutil.IsUniqueConstraintErr(err) {
			return ErrUsernameTaken
		}
		if err != nil {
			return fmt.Errorf("create account: %w", err)
		}
		result.UserID, result.CreatedAt = user.ID, user.CreatedAt

		relPath, dir, err := createHome(ctx, q, params.Files, params.Username, user.ID)
		madeDir = dir
		if err != nil {
			return err
		}
		result.FolderPath = relPath
		return nil
	})
	if err != nil {
		RemoveMadeFolder(ctx, params.Files, madeDir)
		return CreateUserResult{}, err
	}
	return result, nil
}

// RepairHomesParams is the Quark whose accounts are repaired.
type RepairHomesParams struct {
	Database *db.DatabaseSqlc
	// Files is the internal drive's files namespace, where homes live.
	Files vfs.VFS
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
	if params.Files == nil {
		return result, errors.New("files namespace not set")
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
		// The repair ends with the directory there, so one that already exists
		// is adopted rather than refused.
		if _, err := MakeFolder(ctx, params.Files, homeRelPath(account.Username)); err != nil {
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
//
// A token with no live session behind it is an error. A lookup the database
// could not answer is ErrUnavailable, which a caller must not treat as a bad
// token.
func ValidateSession(ctx context.Context, queries *db.Queries, token string) (string, int64, error) {
	digest := hashToken(token)
	session, err := queries.GetSession(ctx, digest)
	if errors.Is(err, sql.ErrNoRows) {
		return "", 0, fmt.Errorf("invalid or expired session")
	}
	if err != nil {
		return "", 0, unavailable("session", err)
	}
	renewSession(ctx, queries, digest, session)
	return session.Username, session.UserID, nil
}

// ValidateBasicAuth checks a username and the account's auth key, sent in the
// password slot, against the user database (#2430). A non-empty password not
// shaped like an auth key is a raw one and returns ErrAppTooOld before any
// lookup.
// Returns the username and user id if valid, or an error if not. Unlike Login,
// this does not create a session, and no login guard stands in front of it:
// it confirms a signed-in caller's key before one sensitive action. The
// per-request Basic fallback in requireAuth uses AuthenticateBasic, which is
// guarded. An account lookup the database could not answer is ErrUnavailable.
func ValidateBasicAuth(ctx context.Context, queries *db.Queries, username, password string) (string, int64, error) {
	if isRawSecret(password) {
		return "", 0, ErrAppTooOld
	}
	user, err := queries.GetUserByUsername(ctx, username)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return "", 0, unavailable("account", err)
	}
	if err != nil || !checkAuthKey(ctx, queries, user, password) {
		return "", 0, fmt.Errorf("invalid credentials")
	}
	if err := statusError(user.Status); err != nil {
		return "", 0, err
	}
	return user.Username, user.ID, nil
}

// AuthenticateBasicParams is one HTTP Basic credential and where it came from.
type AuthenticateBasicParams struct {
	Queries  *db.Queries
	Username string
	// Password is the account's auth key, which Basic carries in its password
	// field (#2430).
	Password string
	// ClientIP is the address the request came from, without a port.
	ClientIP string
	// Guard locks out an address or account after repeated failures; nil
	// checks nothing.
	Guard *ratelimitutil.LoginGuard
}

// AuthenticateBasicResult is the account a Basic credential belongs to.
type AuthenticateBasicResult struct {
	Username string
	UserID   int64
}

// AuthenticateBasic checks an HTTP Basic credential for requireAuth, behind
// Guard exactly as Login is (#2765): a locked-out attempt gets
// *TooManyAttemptsError without its key being checked, every wrong username
// or key counts toward a lockout, and the account's status is checked only
// after the key, so ErrAccountPending and ErrAccountDisabled reach only
// someone who knows it. Unlike Login it creates no session.
//
// A raw password is ErrAppTooOld before anything else is checked, and is not
// counted toward a lockout (#2430). Nor is an account lookup the database
// could not answer, which is ErrUnavailable.
func AuthenticateBasic(ctx context.Context, params AuthenticateBasicParams) (AuthenticateBasicResult, error) {
	if isRawSecret(params.Password) {
		return AuthenticateBasicResult{}, ErrAppTooOld
	}
	attempt := ratelimitutil.LoginAttempt{Account: params.Username, IP: params.ClientIP}
	user, err := guardedAccount(ctx, params.Queries, params.Guard, attempt, params.Password, "")
	if err != nil {
		return AuthenticateBasicResult{}, err
	}
	params.Guard.RecordSuccess(attempt)
	return AuthenticateBasicResult{Username: user.Username, UserID: user.ID}, nil
}

// Logout deletes a session token.
func Logout(ctx context.Context, queries *db.Queries, token string) error {
	return queries.DeleteSession(ctx, hashToken(token))
}

// CheckRecovery returns the id of the account the recovery secret belongs to.
// A recovery key is checked against the recovery key hash. A raw phrase is
// checked against the phrase hash, and only for an account that has no
// recovery key: once it has one, every phrase is refused (#2430).
//
// It returns ErrRecoverySecretRequired unless exactly one secret is given and
// ErrInvalidRecoveryKey for a malformed key. An unknown username and a wrong
// key get the same error as a wrong phrase, so a caller can't learn which
// usernames exist or which secret an account takes; a pending or disabled
// account is refused after the secret, for the same reason Login checks
// status after the auth key.
func CheckRecovery(ctx context.Context, queries *db.Queries, params CheckRecoveryParams) (CheckRecoveryResult, error) {
	if (params.RecoveryPhrase == "") == (params.RecoveryKey == "") {
		return CheckRecoveryResult{}, ErrRecoverySecretRequired
	}
	if params.RecoveryKey != "" {
		if err := validateKey(params.RecoveryKey, ErrInvalidRecoveryKey); err != nil {
			return CheckRecoveryResult{}, err
		}
	}
	user, err := queries.GetUserByUsername(ctx, params.Username)
	if err != nil {
		return CheckRecoveryResult{}, ErrInvalidRecoveryPhrase
	}
	secret, hash := params.RecoveryKey, user.RecoveryKeyHash
	if params.RecoveryKey == "" {
		secret, hash = normalizeRecoveryPhrase(params.RecoveryPhrase), user.RecoveryPhraseHash
		if user.RecoveryKeyHash != "" {
			hash = ""
		}
	}
	if !CheckPassword(secret, hash) {
		return CheckRecoveryResult{}, ErrInvalidRecoveryPhrase
	}
	if err := statusError(user.Status); err != nil {
		return CheckRecoveryResult{}, err
	}
	return CheckRecoveryResult{UserID: user.ID}, nil
}

// SetRecoveryKey stores the signed-in account's recovery key and clears its
// recovery phrase hash, so a phrase the Quark generated or saw stops
// recovering the account (#2430). The key, the cleared phrase and
// params.AfterSet commit together or not at all. It returns
// ErrInvalidRecoveryKey for a malformed key, ErrUserNotFound when the account
// is gone, and ErrNoAuthSalt for an account with no auth salt, since the key
// is derived with it.
func SetRecoveryKey(ctx context.Context, database *db.DatabaseSqlc, params SetRecoveryKeyParams) (SetRecoveryKeyResult, error) {
	if err := validateKey(params.RecoveryKey, ErrInvalidRecoveryKey); err != nil {
		return SetRecoveryKeyResult{}, err
	}
	hash, err := HashKey(params.RecoveryKey)
	if err != nil {
		return SetRecoveryKeyResult{}, err
	}
	// The account is read before the transaction, not in it: a deferred
	// transaction that reads and then writes gets SQLITE_BUSY at once, with no
	// busy wait, when another connection wrote in between (trackDevice's
	// upsert, say). The salt is never cleared, so reading it early is safe.
	user, err := database.Queries.GetUserByID(ctx, params.UserID)
	if errors.Is(err, sql.ErrNoRows) {
		return SetRecoveryKeyResult{}, ErrUserNotFound
	}
	if err != nil {
		return SetRecoveryKeyResult{}, fmt.Errorf("look up the account: %w", err)
	}
	if user.AuthSalt == "" {
		return SetRecoveryKeyResult{}, ErrNoAuthSalt
	}
	err = inTx(ctx, database, func(q *db.Queries) error {
		if err := q.SetRecoveryKey(ctx, db.SetRecoveryKeyParams{RecoveryKeyHash: hash, ID: user.ID}); err != nil {
			return fmt.Errorf("store the recovery key: %w", err)
		}
		if params.AfterSet != nil {
			return params.AfterSet(q, user.ID)
		}
		return nil
	})
	return SetRecoveryKeyResult{}, err
}

// Recover resets a user's password using their recovery phrase or recovery
// key, checked as CheckRecovery does. The new auth key, the new recovery key
// when one is given, the ended sessions, the new session and params.AfterReset
// commit together or not at all. The account keeps the salt it already had,
// which is the one the client derived the new keys with.
//
// The reset clears the password hash, and a new recovery key clears the phrase
// hash, so a legacy phrase recovery leaves no raw secret the Quark saw able to
// sign in or recover (#2430). A phrase without both new keys is an old app's
// recovery and returns ErrAppTooOld.
func Recover(ctx context.Context, database *db.DatabaseSqlc, params RecoverParams) (*LoginResult, error) {
	if params.RecoveryPhrase != "" && (params.NewAuthKey == "" || params.NewRecoveryKey == "") {
		return nil, ErrAppTooOld
	}
	authKeyHash, authSalt, err := newCredentials(params.Username, params.NewAuthKey, params.SaltSecret)
	if err != nil {
		return nil, err
	}
	recoveryKeyHash, err := recoveryKeyHashFor(params.NewRecoveryKey)
	if err != nil {
		return nil, err
	}
	checked, err := CheckRecovery(ctx, database.Queries, CheckRecoveryParams{
		Username:       params.Username,
		RecoveryPhrase: params.RecoveryPhrase,
		RecoveryKey:    params.RecoveryKey,
	})
	if err != nil {
		return nil, err
	}
	userID := checked.UserID

	var token string
	err = inTx(ctx, database, func(q *db.Queries) error {
		user, err := q.GetUserByID(ctx, userID)
		if err != nil {
			return fmt.Errorf("look up the account: %w", err)
		}
		if user.AuthSalt != "" {
			// The salt the client was given, and so derived the new key with.
			authSalt = user.AuthSalt
		}
		if err := q.SetUserCredentials(ctx, db.SetUserCredentialsParams{
			ID:          userID,
			AuthKeyHash: authKeyHash,
			AuthSalt:    authSalt,
		}); err != nil {
			return fmt.Errorf("failed to update password: %w", err)
		}
		if recoveryKeyHash != "" {
			if err := q.SetRecoveryKey(ctx, db.SetRecoveryKeyParams{RecoveryKeyHash: recoveryKeyHash, ID: userID}); err != nil {
				return fmt.Errorf("store the recovery key: %w", err)
			}
		}
		// Invalidate all existing sessions for this user
		if err := q.DeleteUserSessions(ctx, userID); err != nil {
			return fmt.Errorf("failed to invalidate sessions: %w", err)
		}
		if params.AfterReset != nil {
			if err := params.AfterReset(q, userID); err != nil {
				return err
			}
		}
		token, err = newSession(ctx, q, userID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return &LoginResult{SessionToken: token}, nil
}

// ListActiveSessions returns all non-expired sessions for the given user.
// Because tokens are stored as SHA-256 digests, the digest itself is used
// as the opaque session ID exposed to clients. currentID is the id of the
// session the caller is using, which is marked Current; pass "" when the
// caller has none.
func ListActiveSessions(ctx context.Context, queries *db.Queries, userID int64, currentID string) ([]SessionInfo, error) {
	rows, err := queries.ListActiveSessionsForUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to list sessions: %w", err)
	}
	out := make([]SessionInfo, 0, len(rows))
	for _, s := range rows {
		out = append(out, SessionInfo{
			// s.Token is already the SHA-256 digest (stored that way in newSession).
			ID:         s.Token,
			CreatedAt:  s.CreatedAt,
			ExpiresAt:  s.ExpiresAt,
			LastUsedAt: s.LastUsedAt,
			Current:    s.Token == currentID,
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

// RevokeOtherSessions deletes every session of the given user except keepID,
// the id of the session the caller is using. With keepID "" there is nothing
// to keep and every session goes.
func RevokeOtherSessions(ctx context.Context, queries *db.Queries, userID int64, keepID string) error {
	if err := queries.DeleteOtherUserSessions(ctx, db.DeleteOtherUserSessionsParams{UserID: userID, Token: keepID}); err != nil {
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
		result.UserID = target.ID

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
		if err := q.DeleteUserChatKeys(ctx, target.ID); err != nil {
			return fmt.Errorf("delete chat keys: %w", err)
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
