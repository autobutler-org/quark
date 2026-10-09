// Package v0_hostname serves the admin-only /api/v0/hostname routes: reading what the device is called and whether
// it can be renamed, and renaming it.
package v0_hostname

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the hostname routes. Mount it behind
// middleware.RequireAdmin: a rename moves the device to a new address for
// everyone using it (#2344).
func NewRouter() serverutil.Router {
	return &router{}
}
