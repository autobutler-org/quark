package v0_ssh

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the SSH access routes. Mount it behind
// middleware.RequireAdmin: they open a shell login to the device (#2131).
func NewRouter() serverutil.Router {
	return &router{}
}
