package v0_storage

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the routes that change the Quark's drives. Mount it
// behind middleware.RequireAdmin: they affect every account on the Quark.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}
