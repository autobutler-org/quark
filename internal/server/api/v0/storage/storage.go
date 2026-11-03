// Package v0_storage serves /api/v0/storage: the storage devices Quark manages, their snapshot backups, and how
// protected the files are. Reading device status, a backup's progress, and protection status is open to any user;
// renaming a device, setting its role, enabling or disabling a USB device, starting or verifying a backup, and
// restoring the vaults from one are admin-only.
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
