// Package v0_storage serves /api/v0/storage: the storage devices Quark manages and their snapshot backups. Reading
// device status and a backup's progress is open to any user; renaming a device, setting its role, enabling or
// disabling a USB device, and starting or verifying a backup are admin-only.
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
