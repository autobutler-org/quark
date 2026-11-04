package v0_storage

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listDeviceStatuses godoc
// @Summary List storage device statuses
// @Description Returns statuses for all known storage devices. Each device's health object is verdict (healthy, watch, replace-soon, or unknown), reason (one sentence), and when a read succeeded smartStatus, reallocatedSectors, pendingSectors, powerOnHours, temperatureCelsius, media (spinning or solid-state), and linkSpeed. worseThanDefault is true when the verdict is worse than the current default-storage drive (healthy, then watch, then unknown, then replace-soon). health is omitted until a read is attempted. Unknown is never reported as healthy, including when the health tool is not installed. Age is power-on hours; a heavily used drive does not claim a manufacture year.
// @Tags storage
// @Produce json
// @Success 200 {object} object
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /storage/devices/status [get]
func listDeviceStatuses(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	result, err := deviceutil.ListStatuses(deviceutil.ListStatusesParams{
		Ctx:      c.Request.Context(),
		Storage:  deps.StorageService(),
		Database: deps.Database(),
		Registry: deps.VFSRegistry(),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(gin.H{
		"devices": result.Statuses,
		"count":   len(result.Statuses),
	})
}

var listDeviceStatusesRoute = serverutil.ApiRoute(
	"GET", "/storage/devices/status", listDeviceStatuses,
)
