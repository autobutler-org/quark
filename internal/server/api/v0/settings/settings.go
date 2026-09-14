package v0_settings

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the routes that change appliance-wide settings and
// turn remote access on and off. Mount it behind middleware.RequireAdmin: they
// affect every account on the Quark and expose it to the network.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}
