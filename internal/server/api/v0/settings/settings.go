package v0_settings

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the routes that turn remote access on and off. Mount
// it behind middleware.RequireAdmin: they expose the Quark to the network.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}
