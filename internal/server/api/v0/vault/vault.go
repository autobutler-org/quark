package v0_vault

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns every vault route. Mount it behind middleware.RequireAdmin:
// the Quark has one household vault with one process-wide unlock (#1542), so
// until the vault has a design for more than one account, only admins reach it.
func NewRouter() serverutil.Router {
	return &router{}
}
