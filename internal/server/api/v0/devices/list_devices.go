package v0_devices

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listDevices godoc
// @Summary List connected devices
// @Description Returns all unique client IP + User-Agent combinations that have connected to the quark
// @Tags devices
// @Produce json
// @Success 200 {array} ConnectedDeviceJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /devices [get]
func listDevices(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	rows, err := deps.Database().Queries.ListConnectedDevices(c.Request.Context())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	result := make([]ConnectedDeviceJSON, len(rows))
	for i, d := range rows {
		result[i] = ConnectedDeviceJSON{
			ID:           d.ID,
			IPAddress:    d.IpAddress,
			UserAgent:    d.UserAgent,
			FirstSeenAt:  d.FirstSeenAt,
			LastSeenAt:   d.LastSeenAt,
			RequestCount: d.RequestCount,
		}
	}
	return serverutil.Ok().WithData(result)
}

var listDevicesRoute = serverutil.ApiRoute("GET", "/devices", listDevices)
