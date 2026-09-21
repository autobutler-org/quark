package v0_storage

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// startSnapshotBackup godoc
// @Summary Start a snapshot backup to a device
// @Description Aggregates all files from all managed devices onto the target snapshot-backup device
// @Tags storage
// @Accept json
// @Produce json
// @Param body body object true "{targetDeviceSerial: string}"
// @Success 202 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response
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
		Username           string `json:"username"`
		Password           string `json:"password"`
		RecoveryPassword   string `json:"recoveryPassword"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}

	result, err := backup.StartSnapshotBackup(backup.StartSnapshotBackupParams{
		Ctx:                c.Request.Context(),
		Queries:            deps.Database().Queries,
		Storage:            deps.StorageService(),
		Store:              deps.BackupJobStore(),
		EventBus:           deps.EventBus(),
		IOSemaphore:        deps.IOSemaphore(),
		TargetDeviceSerial: req.TargetDeviceSerial,
		Username:           req.Username,
		Password:           req.Password,
		RecoveryPassword:   req.RecoveryPassword,
	})
	var inProgress *backup.BackupInProgressError
	switch {
	case errors.As(err, &inProgress):
		return serverutil.Conflict(err)
	case errors.Is(err, backup.ErrInvalidCredentials),
		errors.Is(err, backup.ErrMasterPasswordMismatch):
		return serverutil.Unauthorized(err)
	case errors.Is(err, backup.ErrTargetRoleRequired),
		errors.Is(err, backup.ErrTargetNotManaged),
		errors.Is(err, backup.ErrVaultCredentialsRequired),
		errors.Is(err, backup.ErrRecoveryPasswordTooShort),
		errors.Is(err, backup.ErrVaultNotInitialized):
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
