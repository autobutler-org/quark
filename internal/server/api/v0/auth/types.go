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

// requestAccountBody is what someone asking for an account sends.
type requestAccountBody struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
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
// logs keep (#2346).
type deleteAccountBody struct {
	Password string `json:"password" binding:"required"`
}

// recoverAccountBody is what POST /auth/recover reads.
type recoverAccountBody struct {
	Username       string `json:"username" binding:"required"`
	RecoveryPhrase string `json:"recoveryPhrase" binding:"required"`
	NewPassword    string `json:"newPassword" binding:"required"`
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
