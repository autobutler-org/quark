package v0_storage

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getSnapshotBackupStatus godoc
// @Summary Get snapshot backup job status
// @Description Returns the current status of a snapshot backup job
// @Tags storage
// @Produce json
// @Param jobId path string true "Job ID"
// @Success 200 {object} object
// @Failure 404 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/status/{jobId} [get]
func getSnapshotBackupStatus(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	jobID := c.Param("jobId")
	job, err := deps.BackupJobStore().Get(c.Request.Context(), jobID)
	if err != nil {
		return serverutil.NotFound(fmt.Errorf("job not found: %w", err))
	}
	return serverutil.Ok().WithData(job)
}

var getSnapshotBackupStatusRoute = serverutil.ApiRoute(
	"GET", "/storage/devices/snapshot-backup/status/:jobId", getSnapshotBackupStatus,
)
