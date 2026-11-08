package v0_storage

import (
	"errors"
	"fmt"
	"io/fs"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// restoreSnapshotFiles godoc
// @Summary Restore files from a snapshot backup
// @Description Queues a snapshot-restore job that copies each device's folder on the drive, which must have the snapshot-backup role, back onto the device it was copied from.
// @Description A file already at the target path is kept as it is: a restore never overwrites. Each copy lands under its name only once it is whole, so a failed restore leaves every file already copied and the rest of the target in place.
// @Description A snapshot never removes a file that left its source, so a restore brings back files deleted since. The folder of a device that is no longer attached goes into a folder of the same name on built-in storage when missingToBuiltIn is true, and is named in missing otherwise.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body restoreSnapshotFilesBody true "The snapshot drive, and whether a gone device's files go to built-in storage"
// @Success 202 {object} backup.StartRestoreFilesResult
// @Failure 400 {object} serverutil.Response "bad request, or a drive without the snapshot-backup role"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "the drive is not attached, or holds no snapshot"
// @Failure 409 {object} serverutil.Response "every device in the snapshot is gone and missingToBuiltIn is false"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/restore-files [post]
func restoreSnapshotFiles(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	var req restoreSnapshotFilesBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}
	userID, _ := ctxutil.Get[int64](c, "userID")

	result, err := backup.StartRestoreFiles(backup.StartRestoreFilesParams{
		Ctx:              c.Request.Context(),
		Queries:          deps.Database().Queries,
		Registry:         deps.VFSRegistry(),
		Queue:            deps.JobQueue(),
		UserID:           userID,
		BackupSerial:     req.DeviceSerial,
		MissingToBuiltIn: req.MissingToBuiltIn,
		Storage:          deps.StorageService(),
	})
	var notFound *fileutil.NotFoundError
	switch {
	case errors.Is(err, backup.ErrRestoreRoleRequired):
		return serverutil.BadRequest(err)
	case errors.As(err, &notFound), errors.Is(err, fs.ErrNotExist), errors.Is(err, backup.ErrNoSnapshot):
		return serverutil.NotFound(err)
	case errors.Is(err, backup.ErrRestoreDevicesMissing):
		return serverutil.Conflict(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	return serverutil.Accepted().WithData(result)
}

var restoreSnapshotFilesRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/snapshot-backup/restore-files", restoreSnapshotFiles,
)
