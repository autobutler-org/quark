package v0_storage

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// renameDevice godoc
// @Summary Rename a storage device
// @Description Sets a custom display name for a storage device identified by its serial number
// @Tags storage
// @Accept json
// @Produce json
// @Param serial query string true "Device serial (empty string for internal device)"
// @Param body body object true "{name: string}"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/rename [patch]
func renameDevice(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	serial := c.Query("serial")

	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	result, err := deviceutil.Rename(deviceutil.RenameParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		Serial:  serial,
		Name:    req.Name,
	})
	switch {
	case errors.Is(err, deviceutil.ErrInvalidDeviceName):
		// The endpoint has never said which rule the name broke; keep it that way.
		return serverutil.BadRequest(nil)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(gin.H{"serial": serial, "name": result.Name})
}

var renameDeviceRoute = serverutil.ApiRoute(
	"PATCH", "/storage/devices/rename", renameDevice,
)
