package v0_admin

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listUsersRoute,
		promoteUserRoute,
		demoteUserRoute,
	}
}

type userSummary struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	IsAdmin  bool   `json:"isAdmin"`
	// Status is pending, active or disabled.
	Status    string `json:"status"`
	CreatedAt string `json:"createdAt"`
}
