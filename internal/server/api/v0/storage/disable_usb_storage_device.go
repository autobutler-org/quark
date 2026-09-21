package v0_storage

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// disableUsbStorageDevice godoc
// @Summary Disable (unmount) a USB storage device
// @Description Unmounts a USB storage device identified by serial
// @Tags storage
// @Produce json
// @Param serial path string true "Device serial"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /storage/devices/usb/{serial} [delete]
func disableUsbStorageDevice(c *gin.Context) *serverutil.Response {
	serial := c.Param("serial")
	if serial == "" {
		return serverutil.BadRequest(errors.New("`serial` path parameter is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	if _, err := deviceutil.Disable(deviceutil.DisableParams{
		Storage: deps.StorageService(),
		Serial:  serial,
	}); err != nil {
		return deviceError(err)
	}

	return serverutil.Ok().WithData(gin.H{
		"message": "USB storage device unmounted successfully",
	})
}

var disableUsbStorageDeviceRoute = serverutil.ApiRoute(
	"DELETE", "/storage/devices/usb/:serial", disableUsbStorageDevice,
)
