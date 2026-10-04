package v0_auth

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		// Local auth
		getAuthStatusRoute,
		setupAuthRoute,
		loginUserRoute,
		getAuthSaltRoute,
		logoutUserRoute,
		recoverAccountRoute,
		recoverChatKeysRoute,
		setRecoveryKeyRoute,
		requestAccountRoute,
		deleteAccountRoute,
		// Session management
		listSessionsRoute,
		revokeSessionRoute,
		revokeAllSessionsRoute,
	}
}

// loginResponse is a successful sign-in.
type loginResponse struct {
	Token string `json:"token"`
	// LegacyRecovery is true for an account that has no recovery key yet, such
	// as one an admin created: the client generates a phrase and sends its key
	// to PUT /auth/recovery-key.
	LegacyRecovery bool `json:"legacyRecovery"`
}

// credentialsBody is what POST /auth/login reads.
type credentialsBody struct {
	Username string `json:"username" binding:"required"`
	// Password, beside AuthKey, upgrades an account that has no auth key yet,
	// once (#2430). Without AuthKey it is an old app's sign-in, refused with
	// 426.
	Password string `json:"password,omitempty"`
	// AuthKey is the standard base64 of the 32-byte key the client derived
	// from the password and the salt GET /auth/salt returned.
	AuthKey string `json:"authKey,omitempty"`
}

// newAccountBody is what POST /auth/setup and POST /auth/request-account
// read: an authKey, and optionally the recoveryKey of a phrase the client
// generated.
type newAccountBody struct {
	Username string `json:"username" binding:"required"`
	// Password is the raw password an app from before auth keys sends. It is
	// refused with 426 (#2430).
	Password string `json:"password,omitempty"`
	// AuthKey is the standard base64 of the 32-byte key the client derived
	// from the password and the salt GET /auth/salt returned.
	AuthKey string `json:"authKey,omitempty"`
	// RecoveryKey is the standard base64 of the 32-byte key the client derived
	// from its recovery phrase and the same salt (#2430). Without it the
	// account has no recovery credential until a sign-in gives it one.
	RecoveryKey string `json:"recoveryKey,omitempty"`
}

// saltResponse is the salt a client derives its auth key with.
type saltResponse struct {
	// Salt is the standard base64 of 16 bytes.
	Salt string `json:"salt"`
	// Legacy is true for an account that has no auth key yet: the client
	// upgrades it by signing in once with the password beside the key (#2430).
	Legacy bool `json:"legacy"`
	// LegacyRecovery is true for an account that has no recovery key: the
	// client gives it one at sign-in, or recovers it once with the raw phrase
	// and a new phrase's key.
	LegacyRecovery bool `json:"legacyRecovery"`
}

// accountRefusal is the 403 body of a sign-in refused for the account's status.
type accountRefusal struct {
	Error string `json:"error"`
	// Status is pending or disabled.
	Status string `json:"status"`
}

// deleteAccountBody is what DELETE /auth/account reads from its body. The
// password field travels here, never in the query string, which access and
// proxy logs keep (#2346). It carries the auth key; a raw password is refused
// with 426 (#2430).
type deleteAccountBody struct {
	Password string `json:"password" binding:"required"`
}

// recoverAccountBody is what POST /auth/recover reads.
type recoverAccountBody struct {
	Username string `json:"username" binding:"required"`
	// RecoveryPhrase is a legacy account's raw phrase, taken once in place of
	// RecoveryKey beside NewAuthKey and NewRecoveryKey (#2430). Without both it
	// is an old app's recovery, refused with 426.
	RecoveryPhrase string `json:"recoveryPhrase,omitempty"`
	// NewPassword is the raw password an app from before auth keys sends. It
	// is refused with 426.
	NewPassword string `json:"newPassword,omitempty"`
	// RecoveryKey is the standard base64 of the 32-byte key derived from the
	// phrase and the salt GET /auth/salt returned (#2430).
	RecoveryKey string `json:"recoveryKey,omitempty"`
	// NewAuthKey is the standard base64 of the 32-byte key derived from the
	// new password and the salt GET /auth/salt returned (#2430).
	NewAuthKey string `json:"newAuthKey,omitempty"`
	// NewRecoveryKey is the standard base64 of the 32-byte key derived from a
	// phrase the client just generated and the same salt. A legacy phrase
	// recovery must carry it, so the account leaves the phrase the Quark saw.
	NewRecoveryKey string `json:"newRecoveryKey,omitempty"`
	// ChatKeys is the account's chat identity re-wrapped under the new
	// password, stored in the same transaction as the reset (#2416). Absent
	// leaves the stored keys as they are.
	ChatKeys *chatutil.Keys `json:"chatKeys,omitempty"`
}

// recoverChatKeysBody is what POST /auth/recover/keys reads: the recoveryKey,
// or a legacy account's recoveryPhrase, as POST /auth/recover takes them.
type recoverChatKeysBody struct {
	Username string `json:"username" binding:"required"`
	// RecoveryPhrase is the raw phrase of an account that has no recovery key
	// yet (#2430). An account with one refuses it as a wrong phrase.
	RecoveryPhrase string `json:"recoveryPhrase,omitempty"`
	RecoveryKey    string `json:"recoveryKey,omitempty"`
}

// setRecoveryKeyBody is what PUT /auth/recovery-key reads.
type setRecoveryKeyBody struct {
	// Password re-confirms the caller with its auth key, so a session alone
	// cannot replace the recovery credential, as delete-account takes it. A
	// raw password is refused with 426 (#2430).
	Password string `json:"password"`
	// RecoveryKey is the standard base64 of the 32-byte key the client derived
	// from the phrase it generated and the account's auth salt.
	RecoveryKey string `json:"recoveryKey" binding:"required"`
	// ChatKeys is the account's chat identity re-wrapped under the new
	// phrase, stored in the same transaction. Absent leaves the stored keys as
	// they are.
	ChatKeys *chatutil.Keys `json:"chatKeys,omitempty"`
}
