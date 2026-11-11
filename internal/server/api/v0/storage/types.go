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
		restoreSnapshotChatRoute,
		restoreSnapshotFilesRoute,
		listBackupRunsRoute,
		deleteBackupRunRoute,
		getBackupScheduleRoute,
		setBackupScheduleRoute,
	}
}

// setBackupScheduleBody is what setting a backup drive's schedule reads.
type setBackupScheduleBody struct {
	// "" is built-in storage, so the field is not binding:"required".
	DeviceSerial string `json:"deviceSerial"`
	// Cadence is off, daily, weekly or monthly.
	Cadence string `json:"cadence"`
	// SourceSerials are the data drives to copy; empty is every data drive.
	SourceSerials []string `json:"sourceSerials"`
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

// restoreSnapshotBody is what the vault and chat restores read.
type restoreSnapshotBody struct {
	// "" is built-in storage, so the field is not binding:"required".
	DeviceSerial string `json:"deviceSerial"`
	// Password is the standard base64 auth key of the admin's login
	// password, as DELETE /vault takes it.
	Password string `json:"password"`
	// Run is the run to restore from, a folder under backups/ on the drive.
	// Empty is the newest complete run.
	Run string `json:"run"`
}

// maxRestoreRequestBytes bounds a restore's body, a serial, a run and an auth
// key.
const maxRestoreRequestBytes = 1 << 10
