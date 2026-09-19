package v0_auth

import (
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
		requestAccountRoute,
		deleteAccountRoute,
		// Session management
		listSessionsRoute,
		revokeSessionRoute,
		revokeAllSessionsRoute,
	}
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
