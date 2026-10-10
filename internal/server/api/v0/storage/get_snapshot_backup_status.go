package v0_storage

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getSnapshotBackupStatus godoc
// @Summary Get snapshot backup job status
// @Description Returns the current status of a snapshot backup job, read from its row in the jobs table, so any instance answers and a backup cut off by a restart reads as FAILED. 404 means the id is not a backup job's.
// @Tags storage
// @Produce json
// @Param jobId path string true "Job ID"
// @Success 200 {object} backup.BackupJob
// @Failure 404 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/status/{jobId} [get]
func getSnapshotBackupStatus(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	result, err := backup.GetSnapshotBackupStatus(backup.GetSnapshotBackupStatusParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		JobID:   c.Param("jobId"),
	})
	if errors.Is(err, backup.ErrBackupJobNotFound) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result.Job)
}

var getSnapshotBackupStatusRoute = serverutil.ApiRoute(
	"GET", "/storage/devices/snapshot-backup/status/:jobId", getSnapshotBackupStatus,
)
