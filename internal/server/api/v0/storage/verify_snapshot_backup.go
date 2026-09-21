package v0_storage

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// verifySnapshotBackup godoc
// @Summary Verify integrity of a snapshot backup
// @Description Walks all files on the backup device and checks against the manifest
// @Tags storage
// @Accept json
// @Produce json
// @Param body body object true "{deviceSerial: string, full: bool}"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/verify [post]
func verifySnapshotBackup(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		DeviceSerial string `json:"deviceSerial" binding:"required"`
		Full         bool   `json:"full"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	dev, err := deps.StorageService().FindManagedDeviceBySerial(req.DeviceSerial)
	if err != nil || dev == nil {
		return serverutil.BadRequest(fmt.Errorf("device not found"))
	}

	result, err := backup.VerifyBackup(dev.FilesDir, req.Full)
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("verify failed: %w", err))
	}

	return serverutil.Ok().WithData(result)
}

var verifySnapshotBackupRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/snapshot-backup/verify", verifySnapshotBackup,
)
