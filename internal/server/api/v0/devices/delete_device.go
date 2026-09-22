package v0_devices

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// deleteDevice godoc
// @Summary Remove a connected device record
// @Description Deletes a connected device entry by ID
// @Tags devices
// @Param id path int true "Device ID"
// @Success 200 {object} serverutil.Response
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /devices/{id} [delete]
func deleteDevice(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(err)
	}
	if err := deps.Database().Queries.DeleteConnectedDevice(c.Request.Context(), id); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

var deleteDeviceRoute = serverutil.ApiRoute("DELETE", "/devices/:id", deleteDevice)
