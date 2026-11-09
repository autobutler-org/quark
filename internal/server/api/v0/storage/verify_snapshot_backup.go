package v0_storage

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// verifySnapshotBackup godoc
// @Summary Verify integrity of a snapshot backup
// @Description Checks one run on the backup device, a folder under backups/, against the manifest it holds: by size, or by SHA-256 when full is true.
// @Description run names the run; empty is the newest complete one. A run still being written is never verified. The answer names the run it checked.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body verifySnapshotBackupBody true "The backup drive, the run, and whether to hash every file"
// @Success 200 {object} backup.VerifyResult
// @Failure 400 {object} serverutil.Response "bad request, or a drive with no complete run"
// @Failure 404 {object} serverutil.Response "the device is not attached, or holds no complete run of that name"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/verify [post]
func verifySnapshotBackup(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req verifySnapshotBackupBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	result, err := backup.VerifyBackup(backup.VerifyBackupParams{
		Ctx:          c.Request.Context(),
		Registry:     deps.VFSRegistry(),
		DeviceSerial: req.DeviceSerial,
		Full:         req.Full,
		Run:          req.Run,
	})
	var notFound *fileutil.NotFoundError
	switch {
	case errors.As(err, &notFound), errors.Is(err, backup.ErrRunNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, backup.ErrNoManifest):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.BadRequest(fmt.Errorf("verify failed: %w", err))
	}

	return serverutil.Ok().WithData(result)
}

var verifySnapshotBackupRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/snapshot-backup/verify", verifySnapshotBackup,
)
