package v0_storage

import (
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listBackupRuns godoc
// @Summary List the backups on a backup drive
// @Description Lists the complete runs on a drive with the snapshot-backup role, newest first: each run's folder under backups/, when it completed, its size, and the drive folders it holds. A run still being written is not listed. A drive with no backups lists none.
// @Description sizeBytes is the bytes the run's files hold, from its manifest. A file unchanged between runs is one hard-linked file counted in each, so deleting one run frees less space than its size.
// @Tags storage
// @Produce json
// @Param deviceSerial query string false "The backup drive's serial; empty or absent is built-in storage"
// @Success 200 {object} backup.ListDriveRunsResult
// @Failure 400 {object} serverutil.Response "a drive without the snapshot-backup role"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "the drive is not attached"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/runs [get]
func listBackupRuns(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	result, err := backup.ListDriveRuns(backup.ListDriveRunsParams{
		Ctx:          c.Request.Context(),
		Queries:      deps.Database().Queries,
		Registry:     deps.VFSRegistry(),
		DeviceSerial: c.Query("deviceSerial"),
	})
	if err != nil {
		return backupRunsError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listBackupRunsRoute = serverutil.ApiRoute(
	"GET", "/storage/devices/snapshot-backup/runs", listBackupRuns,
)
