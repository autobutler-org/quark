package v0_storage

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// setBackupSchedule godoc
// @Summary Set a backup drive's schedule
// @Description Sets how often the Quark backs up onto a drive with the snapshot-backup role, which need not be attached. cadence is off, daily, weekly or monthly; anything else is a 400. sourceSerials names the data drives to copy, built-in storage as ""; empty or absent is every data drive. A source that is the drive itself or another snapshot-backup drive is a 400. A source that is not attached is kept, and left out of a backup while it is away.
// @Description Every 15 minutes, and whenever a drive is plugged in or removed, the Quark starts a backup onto each attached drive whose schedule is due, as GET /storage/devices/snapshot-backup/schedule reports it. It skips a drive with a backup already pending or running, and a drive whose health.verdict is replace-soon, which still needs a backup started by hand with acknowledgeHealth. When the schedule set here is due and the drive is attached, the backup starts at once and jobId names it. Publishes backup_schedule_changed with the drive's serial.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body setBackupScheduleBody true "The backup drive and its schedule"
// @Success 200 {object} backup.SetScheduleResult
// @Failure 400 {object} serverutil.Response "bad request, an unknown cadence, a drive without the snapshot-backup role, or a source that is not a data drive"
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/schedule [put]
func setBackupSchedule(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	var req setBackupScheduleBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}
	result, err := backup.SetSchedule(backup.SetScheduleParams{
		Ctx:           c.Request.Context(),
		Queries:       deps.Database().Queries,
		Registry:      deps.VFSRegistry(),
		Queue:         deps.JobQueue(),
		Storage:       deps.StorageService(),
		EventBus:      deps.EventBus(),
		DeviceSerial:  req.DeviceSerial,
		Cadence:       req.Cadence,
		SourceSerials: req.SourceSerials,
	})
	if err != nil {
		return backupScheduleError(err)
	}
	return serverutil.Ok().WithData(result)
}

var setBackupScheduleRoute = serverutil.ApiRoute(
	"PUT", "/storage/devices/snapshot-backup/schedule", setBackupSchedule,
)
