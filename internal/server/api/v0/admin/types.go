package v0_admin

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listUsersRoute,
		createUserRoute,
		promoteUserRoute,
		demoteUserRoute,
		approveUserRoute,
		denyUserRoute,
		disableUserRoute,
		enableUserRoute,
		deleteUserRoute,
	}
}

// deleteUserResponse reports how many owned paths the deleting admin inherited.
type deleteUserResponse struct {
	OwnerRowsReassigned int64 `json:"ownerRowsReassigned"`
}

// createUserBody is an account an admin adds. Every account gets a home named
// after it, so there is nothing to ask for here (#1908).
type createUserBody struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type userSummary struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	IsAdmin  bool   `json:"isAdmin"`
	// Status is pending, active or disabled.
	Status    string `json:"status"`
	CreatedAt string `json:"createdAt"`
}
