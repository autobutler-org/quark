package v0_version

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the route that updates the Quark. Mount it behind
// middleware.RequireAdmin: it installs software and restarts the appliance.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}
