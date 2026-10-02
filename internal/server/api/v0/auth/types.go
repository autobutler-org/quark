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
}

// credentialsBody is what POST /auth/login and POST /auth/setup read. Setup
// takes exactly one of password and authKey. Login takes either, or both to
// upgrade an account that has no auth key yet (#2430).
type credentialsBody struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password,omitempty"`
	// AuthKey is the standard base64 of the 32-byte key the client derived
	// from the password and the salt GET /auth/salt returned.
	AuthKey string `json:"authKey,omitempty"`
}

// saltResponse is the salt a client derives its auth key with.
type saltResponse struct {
	// Salt is the standard base64 of 16 bytes.
	Salt string `json:"salt"`
	// Legacy is true for an account that has no auth key yet: the client signs
	// in with both password and authKey to give it one.
	Legacy bool `json:"legacy"`
}

// requestAccountBody is what someone asking for an account sends: exactly one
// of password and authKey.
type requestAccountBody struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password,omitempty"`
	// AuthKey is the standard base64 of the 32-byte key the client derived
	// from the password and the salt GET /auth/salt returned.
	AuthKey string `json:"authKey,omitempty"`
}

// requestAccountResponse carries the requester's recovery phrase, shown once.
type requestAccountResponse struct {
	RecoveryPhrase string `json:"recoveryPhrase"`
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
	Username       string `json:"username" binding:"required"`
	RecoveryPhrase string `json:"recoveryPhrase" binding:"required"`
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

// recoverChatKeysBody is what POST /auth/recover/keys reads.
type recoverChatKeysBody struct {
	Username       string `json:"username" binding:"required"`
	RecoveryPhrase string `json:"recoveryPhrase" binding:"required"`
}
