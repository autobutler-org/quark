package v0_storage

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// router holds the read-only routes that describe the Quark's storage.
type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listDeviceStatusesRoute,
		getProtectionStatusRoute,
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
		restoreSnapshotVaultRoute,
		restoreSnapshotFilesRoute,
		listBackupRunsRoute,
		deleteBackupRunRoute,
	}
}

// deleteBackupRunBody is what deleting a backup run reads.
type deleteBackupRunBody struct {
	// "" is built-in storage, so the field is not binding:"required".
	DeviceSerial string `json:"deviceSerial"`
	// Run is the run's folder under backups/ on the drive. Any name that
	// is not a listed run, empty included, is 404.
	Run string `json:"run"`
}

// restoreSnapshotFilesBody is what the file restore reads.
type restoreSnapshotFilesBody struct {
	// "" is built-in storage, so the field is not binding:"required".
	DeviceSerial string `json:"deviceSerial"`
	// MissingToBuiltIn puts the files of a device that is no longer attached
	// on built-in storage.
	MissingToBuiltIn bool `json:"missingToBuiltIn"`
	// Run is the run to restore, a folder under backups/ on the drive. Empty
	// is the newest complete run.
	Run string `json:"run"`
}

// verifySnapshotBackupBody is what the verify reads.
type verifySnapshotBackupBody struct {
	// "" is built-in storage, so the field is not binding:"required".
	DeviceSerial string `json:"deviceSerial"`
	// Full hashes every file; otherwise only sizes are compared.
	Full bool `json:"full"`
	// Run is the run to verify, a folder under backups/ on the drive. Empty
	// is the newest complete run.
	Run string `json:"run"`
}
