package v0_storage

import (
	"time"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// ProtectionStatus is the body of GET /storage/protection.
type ProtectionStatus struct {
	// Level is the weakest data drive's: unprotected, basic, or protected.
	Level string `json:"level" enums:"unprotected,basic,protected"`
	// Sentence is one plain sentence describing the whole Quark from its weakest data drive.
	Sentence string `json:"sentence"`
	// NextStep is assign-backup-role, start-backup, or keep-one-elsewhere.
	NextStep string `json:"nextStep" enums:"assign-backup-role,start-backup,keep-one-elsewhere"`
	// DataDrives lists every connected drive that is not a backup drive, built-in storage first.
	DataDrives []ProtectionDataDrive `json:"dataDrives"`
	// BackupDrives lists every snapshot-backup drive, connected or not.
	BackupDrives []ProtectionBackupDrive `json:"backupDrives"`
}

// ProtectionDataDrive is one drive holding files, and the copies of it.
type ProtectionDataDrive struct {
	// Serial is empty for built-in storage.
	Serial string `json:"serial"`
	Name   string `json:"name"`
	// Level is unprotected (no counting copy), basic (one), or protected (two or more).
	Level string `json:"level" enums:"unprotected,basic,protected"`
	// Copies is one per backup drive with a copy of this drive, newest first.
	Copies []ProtectionCopy `json:"copies"`
}

// ProtectionCopy is one backup drive's copy of a data drive.
type ProtectionCopy struct {
	BackupSerial string    `json:"backupSerial"`
	BackupName   string    `json:"backupName"`
	CopiedAt     time.Time `json:"copiedAt"`
	// Counts is whether this copy protects the drive.
	Counts bool `json:"counts"`
	// Reason is why Counts is false, in one plain sentence. Empty when Counts is true.
	Reason string `json:"reason"`
}

// ProtectionBackupDrive is one snapshot-backup drive and what it holds.
type ProtectionBackupDrive struct {
	Serial string `json:"serial"`
	Name   string `json:"name"`
	// State is retired, receiving, away, no-copies, current, or behind; the first that applies.
	State string `json:"state" enums:"no-copies,receiving,current,behind,away,retired"`
	// Holds is one per current data drive this drive has a copy of, newest first.
	Holds []ProtectionHeldCopy `json:"holds"`
	// NewestCopy is the newest of Holds. Null when Holds is empty.
	NewestCopy *time.Time `json:"newestCopy"`
}

// ProtectionHeldCopy is one data drive a backup drive holds a copy of.
type ProtectionHeldCopy struct {
	Serial   string    `json:"serial"`
	Name     string    `json:"name"`
	CopiedAt time.Time `json:"copiedAt"`
}

// getProtectionStatus godoc
// @Summary Get data protection status
// @Description Reports how protected the files are, per drive. A data drive is every connected drive that is not a snapshot-backup drive: built-in storage, the default-storage drive, and unassigned drives. A backup drive is every snapshot-backup drive, connected or not. A backup drive's copy of a data drive is its newest complete run folder under backups/ whose manifest names that data drive, dated when the run completed. An attached backup drive's run folders are read on every request, and a backup drive that is away answers from the scan cached when it was last attached; one never scanned has no copies. A copy counts when the backup drive's health verdict is not replace-soon, the copy is inside 30 days, and the backup drive is on a different physical disk from the data drive; two partitions of one backup disk count once per data drive. A data drive with no counting copy is unprotected, one is basic, and two or more is protected. level is the weakest data drive's. sentence is one plain sentence. nextStep is start-backup when a backup drive could give the weakest data drive another counting copy, assign-backup-role when none can, and keep-one-elsewhere when every data drive is protected. dataDrives lists each data drive's copies with whether each counts and why not. backupDrives lists each backup drive's state (retired, receiving, away, no-copies, current, or behind, first match wins) and the data drives it holds. Refetch when a backup completes or fails (backup_completed, backup_failed).
// @Tags storage
// @Produce json
// @Success 200 {object} ProtectionStatus
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /storage/protection [get]
func getProtectionStatus(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil || deps.StorageService() == nil {
		return serverutil.InternalServerError(nil)
	}

	result, err := protectionStatus(c.Request.Context(), deps)
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(protectionResponse(result))
}

var getProtectionStatusRoute = serverutil.ApiRoute(
	"GET", "/storage/protection", getProtectionStatus,
)
