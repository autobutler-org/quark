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
	}
}

// createUserBody is an account an admin adds.
type createUserBody struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
	// CreateFolder makes a private folder named after the account, owned by it.
	CreateFolder bool `json:"createFolder"`
}

type userSummary struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	IsAdmin  bool   `json:"isAdmin"`
	// Status is pending, active or disabled.
	Status    string `json:"status"`
	CreatedAt string `json:"createdAt"`
}
