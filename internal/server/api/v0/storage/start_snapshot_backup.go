package v0_storage

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// startSnapshotBackup godoc
// @Summary Start a snapshot backup to a device
// @Description Queues a job that copies the data drives onto the target snapshot-backup device. sourceSerials names the data drives to copy; empty or absent is every data drive, every managed device but the target and the other snapshot-backup drives. Built-in storage is the serial "", as it is for targetDeviceSerial. Each named serial must be an attached data drive; the target, another snapshot-backup drive, or a drive that is not attached is a 400. The job name and the run name only the drives copied. Answers 409 while the target already has a pending or running backup, whichever instance started it, and 409 when the target's health.verdict is replace-soon unless acknowledgeHealth is true. Watch does not block. It asks for no password. On SQLite the snapshot also copies the chat and every account's vault, as the ciphertext they are, into chat_backup.db and vault_items_backup.db. On PostgreSQL the snapshot is the device directories and backup_manifest.json only: the chat and the vault are in the operator's database backup.
// @Description Each backup is a new run in its own folder under backups/, named for the minute it started in the Quark's local time, as "2026-11-07 21.57", with " (2)" and so on when two start in the same minute. A run holds one folder per source drive ("Built-in storage", or the drive's name and the first 8 characters of its serial, as "Photos (USB 90C82C65)"), the chat and vault files, and the manifest, which records each drive folder's source serial.
// @Description A run is written under a hidden folder ending in .partial and renamed when it completes; a failed or canceled run's partial folder is removed. A file unchanged since the newest complete run holding its drive is hard-linked from it where the drive's filesystem allows, and copied otherwise. No source's own backups/ folder is copied. The backup never deletes a file. jobId is what the status route takes.
// @Description Before copying, the backup compares the drive's free space with the bytes the run will copy, every file it cannot hard-link. While that is short it deletes the oldest complete run, one at a time, and publishes backup_deleted for each; it never deletes the newest complete run, nor the newest run holding any drive (a drive's newest copy), nor a run a restore is reading. If the drive is still short, the backup fails before copying with a message naming the drive, such as "not enough space on Backup for this backup: delete old backups or use a bigger drive". A drive whose free space cannot be read is not pruned.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body object true "{targetDeviceSerial: string, sourceSerials: []string, acknowledgeHealth: bool}"
// @Success 202 {object} object
// @Failure 400 {object} serverutil.Response "target without the role or not attached, or a source that is not an attached data drive"
// @Failure 409 {object} serverutil.Response "backup already running, or a replace-soon target was not acknowledged"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup [post]
func startSnapshotBackup(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		// "" is built-in storage, so the field is not binding:"required".
		TargetDeviceSerial string   `json:"targetDeviceSerial"`
		SourceSerials      []string `json:"sourceSerials"`
		AcknowledgeHealth  bool     `json:"acknowledgeHealth"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}

	// The account the job is recorded under. Absent means 0, a system job.
	userID, _ := ctxutil.Get[int64](c, "userID")
	// A target that does not hold the role keeps the role error. A Replace soon
	// target that does is refused until acknowledgeHealth is set.
	if role, err := deps.Database().Queries.GetDeviceRole(c.Request.Context(), req.TargetDeviceSerial); err == nil && role == "snapshot-backup" {
		if err := deviceutil.RefuseReplaceSoonTarget(deviceutil.BackupHealthParams{
			Ctx:               c.Request.Context(),
			Storage:           deps.StorageService(),
			Serial:            req.TargetDeviceSerial,
			AcknowledgeHealth: req.AcknowledgeHealth,
		}); err != nil {
			return deviceError(err)
		}
	}
	result, err := backup.StartSnapshotBackup(backup.StartSnapshotBackupParams{
		Ctx:                c.Request.Context(),
		Queries:            deps.Database().Queries,
		Registry:           deps.VFSRegistry(),
		Queue:              deps.JobQueue(),
		UserID:             userID,
		TargetDeviceSerial: req.TargetDeviceSerial,
		SourceSerials:      req.SourceSerials,
		Storage:            deps.StorageService(),
	})
	var inProgress *backup.BackupInProgressError
	switch {
	case errors.As(err, &inProgress):
		return serverutil.Conflict(err)
	case errors.Is(err, backup.ErrTargetRoleRequired),
		errors.Is(err, backup.ErrTargetNotManaged),
		errors.Is(err, backup.ErrSourceNotDataDrive):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	return serverutil.Accepted().WithData(gin.H{
		"jobId": result.JobID,
	})
}

var startSnapshotBackupRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/snapshot-backup", startSnapshotBackup,
)
