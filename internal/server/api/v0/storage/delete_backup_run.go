package v0_storage

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// deleteBackupRun godoc
// @Summary Delete a backup from a backup drive
// @Description Permanently deletes one complete run, a folder under backups/ on a drive with the snapshot-backup role, as GET /storage/devices/snapshot-backup/runs names it. It does not go to the trash. Every run is complete on its own, so no other run loses a file, and because unchanged files are hard-linked between runs, the space freed can be less than the run's size.
// @Description Only a listed run is deleted: any other name, a run still being written or a path out of backups/ included, is 404. While a backup onto the drive is pending or running, or a restore reads the run, it is 409. The drive's protection status reads without the run afterwards, and backup_deleted is published with the drive's serial and the run.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body deleteBackupRunBody true "The backup drive and the run"
// @Success 200 {object} backup.DeleteRunResult
// @Failure 400 {object} serverutil.Response "bad request, or a drive without the snapshot-backup role"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "the drive is not attached, or holds no complete run of that name"
// @Failure 409 {object} serverutil.Response "a backup onto the drive or a restore of the run is pending or running"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/runs [delete]
func deleteBackupRun(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	var req deleteBackupRunBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}
	result, err := backup.DeleteRun(backup.DeleteRunParams{
		Ctx:          c.Request.Context(),
		Queries:      deps.Database().Queries,
		Registry:     deps.VFSRegistry(),
		EventBus:     deps.EventBus(),
		DeviceSerial: req.DeviceSerial,
		Run:          req.Run,
	})
	if err != nil {
		return backupRunsError(err)
	}
	return serverutil.Ok().WithData(result)
}

var deleteBackupRunRoute = serverutil.ApiRoute(
	"DELETE", "/storage/devices/snapshot-backup/runs", deleteBackupRun,
)
