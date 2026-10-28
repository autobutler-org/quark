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
// @Description Queues a job that aggregates all files from all managed devices onto the target snapshot-backup device. Answers 409 while the target already has a pending or running backup, whichever instance started it, and 409 when the target's health.verdict is replace-soon unless acknowledgeHealth is true. Watch does not block. It asks for no password. On SQLite the snapshot also copies the chat and every account's vault, as the ciphertext they are, into chat_backup.db and vault_items_backup.db. On PostgreSQL the snapshot is the device directories and backup_manifest.json only: the chat and the vault are in the operator's database backup. The backup does not delete files already on the drive; it removes only its own temp files and, on PostgreSQL, a chat_backup.db or vault_items_backup.db an earlier snapshot left at the drive's root. jobId is what the status route takes.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body object true "{targetDeviceSerial: string, acknowledgeHealth: bool}"
// @Success 202 {object} object
// @Failure 400 {object} serverutil.Response
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
		TargetDeviceSerial string `json:"targetDeviceSerial" binding:"required"`
		AcknowledgeHealth  bool   `json:"acknowledgeHealth"`
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
	})
	var inProgress *backup.BackupInProgressError
	switch {
	case errors.As(err, &inProgress):
		return serverutil.Conflict(err)
	case errors.Is(err, backup.ErrTargetRoleRequired),
		errors.Is(err, backup.ErrTargetNotManaged):
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
