// Package v0_version serves /api/v0/version: the installed version, the SBOM, the versions available, and, for
// admins, updating to one.
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
