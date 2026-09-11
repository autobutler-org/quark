// Package v0_trash serves /api/v0/trash: listing a device's trash, restoring
// items to where they were deleted from, and deleting them for good.
package v0_trash

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the router for the trash routes.
func NewRouter() serverutil.Router {
	return &router{}
}
