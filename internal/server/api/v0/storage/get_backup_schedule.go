package v0_storage

import (
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getBackupSchedule godoc
// @Summary Read a backup drive's schedule
// @Description Reads how often the Quark backs up onto a drive with the snapshot-backup role. cadence is off, daily, weekly or monthly, off when none was set. sourceSerials are the data drives the schedule copies, built-in storage as ""; empty is every data drive.
// @Description due is true when the cadence is not off and the newest run on the drive holding a scheduled source (any run, when every data drive is scheduled) completed longer ago than the cadence (24 hours, 7 days, 30 days), or there is none. The runs are read from the drive when it is attached and from its last scan when it is away. waitingForDrive is true when the backup is due and the drive is not attached: it starts once the drive is plugged in.
// @Tags storage
// @Produce json
// @Param deviceSerial query string false "The backup drive's serial; empty or absent is built-in storage"
// @Success 200 {object} backup.GetScheduleResult
// @Failure 400 {object} serverutil.Response "a drive without the snapshot-backup role"
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/schedule [get]
func getBackupSchedule(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	result, err := backup.GetSchedule(backup.GetScheduleParams{
		Ctx:          c.Request.Context(),
		Queries:      deps.Database().Queries,
		Registry:     deps.VFSRegistry(),
		DeviceSerial: c.Query("deviceSerial"),
	})
	if err != nil {
		return backupScheduleError(err)
	}
	return serverutil.Ok().WithData(result)
}

var getBackupScheduleRoute = serverutil.ApiRoute(
	"GET", "/storage/devices/snapshot-backup/schedule", getBackupSchedule,
)
