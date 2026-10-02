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
	// RecoveryPhrase is present only on the first sign-in of an account an
	// admin created.
	RecoveryPhrase string `json:"recoveryPhrase,omitempty"`
	// LegacyRecovery is true for an account that has no recovery key yet: the
	// client generates a phrase and sends its key to PUT /auth/recovery-key.
	LegacyRecovery bool `json:"legacyRecovery"`
}

// credentialsBody is what POST /auth/login reads: a password or an authKey,
// or both to upgrade an account that has no auth key yet (#2430).
type credentialsBody struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password,omitempty"`
	// AuthKey is the standard base64 of the 32-byte key the client derived
	// from the password and the salt GET /auth/salt returned.
	AuthKey string `json:"authKey,omitempty"`
}

// newAccountBody is what POST /auth/setup and POST /auth/request-account
// read: exactly one of password and authKey, and with authKey optionally the
// recoveryKey of a phrase the client generated.
type newAccountBody struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password,omitempty"`
	// AuthKey is the standard base64 of the 32-byte key the client derived
	// from the password and the salt GET /auth/salt returned.
	AuthKey string `json:"authKey,omitempty"`
	// RecoveryKey is the standard base64 of the 32-byte key the client derived
	// from its recovery phrase and the same salt. With it the Quark makes no
	// phrase (#2430).
	RecoveryKey string `json:"recoveryKey,omitempty"`
}

// saltResponse is the salt a client derives its auth key with.
type saltResponse struct {
	// Salt is the standard base64 of 16 bytes.
	Salt string `json:"salt"`
	// Legacy is true for an account that has no auth key yet: the client signs
	// in with both password and authKey to give it one.
	Legacy bool `json:"legacy"`
	// LegacyRecovery is true for an account that has no recovery key yet: it
	// recovers with its raw phrase, and the client gives it a new phrase.
	LegacyRecovery bool `json:"legacyRecovery"`
}

// requestAccountResponse carries the requester's recovery phrase, shown once.
// It is absent when the request carried a recoveryKey.
type requestAccountResponse struct {
	RecoveryPhrase string `json:"recoveryPhrase,omitempty"`
}

// accountRefusal is the 403 body of a sign-in refused for the account's status.
type accountRefusal struct {
	Error string `json:"error"`
	// Status is pending or disabled.
	Status string `json:"status"`
}

// deleteAccountBody is what DELETE /auth/account reads from its body. The
// password travels here, never in the query string, which access and proxy
// logs keep (#2346). A client that signs in with an auth key sends that key
// as the password (#2430).
type deleteAccountBody struct {
	Password string `json:"password" binding:"required"`
}

// recoverAccountBody is what POST /auth/recover reads.
type recoverAccountBody struct {
	Username string `json:"username" binding:"required"`
	// Exactly one of RecoveryPhrase and RecoveryKey is sent. RecoveryKey is
	// the standard base64 of the 32-byte key derived from the phrase and the
	// salt GET /auth/salt returned (#2430).
	RecoveryPhrase string `json:"recoveryPhrase,omitempty"`
	RecoveryKey    string `json:"recoveryKey,omitempty"`
	// NewRecoveryKey, sent only with NewAuthKey, replaces the recovery
	// credential in the same transaction and clears the old phrase.
	NewRecoveryKey string `json:"newRecoveryKey,omitempty"`
	// Exactly one of NewPassword and NewAuthKey is sent. NewAuthKey is the
	// standard base64 of the 32-byte key derived from the new password and the
	// salt GET /auth/salt returned (#2430).
	NewPassword string `json:"newPassword,omitempty"`
	NewAuthKey  string `json:"newAuthKey,omitempty"`
	// ChatKeys is the account's chat identity re-wrapped under NewPassword,
	// stored in the same transaction as the reset (#2416). Absent leaves the
	// stored keys as they are.
	ChatKeys *chatutil.Keys `json:"chatKeys,omitempty"`
}

// recoverChatKeysBody is what POST /auth/recover/keys reads: exactly one of
// RecoveryPhrase and RecoveryKey, as POST /auth/recover takes them.
type recoverChatKeysBody struct {
	Username       string `json:"username" binding:"required"`
	RecoveryPhrase string `json:"recoveryPhrase,omitempty"`
	RecoveryKey    string `json:"recoveryKey,omitempty"`
}

// setRecoveryKeyBody is what PUT /auth/recovery-key reads.
type setRecoveryKeyBody struct {
	// Password re-confirms the caller, so a session alone cannot replace the
	// recovery credential. A client that signs in with an auth key sends that
	// key here, as delete-account takes it.
	Password string `json:"password"`
	// RecoveryKey is the standard base64 of the 32-byte key the client derived
	// from the phrase it generated and the account's auth salt.
	RecoveryKey string `json:"recoveryKey" binding:"required"`
	// ChatKeys is the account's chat identity re-wrapped under the new
	// phrase, stored in the same transaction. Absent leaves the stored keys as
	// they are.
	ChatKeys *chatutil.Keys `json:"chatKeys,omitempty"`
}
