package v0_storage

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// router holds the read-only routes that describe the Quark's storage.
type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listDeviceStatusesRoute,
		getSnapshotBackupStatusRoute,
	}
}

// adminRouter holds the routes that mount, re-role, rename or back up drives.
type adminRouter struct{}

func (r *adminRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		disableUsbStorageDeviceRoute,
		enableUsbStorageDeviceRoute,
		renameDeviceRoute,
		setDeviceRoleRoute,
		startSnapshotBackupRoute,
		verifySnapshotBackupRoute,
	}
}
