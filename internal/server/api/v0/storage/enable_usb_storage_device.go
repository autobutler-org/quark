package v0_storage

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// enableUsbStorageDevice godoc
// @Summary Enable (mount) a USB storage device
// @Description Mounts a USB storage device identified by serial and returns mount info
// @Tags storage
// @Produce json
// @Param serial path string true "Device serial"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /storage/devices/usb/{serial} [post]
func enableUsbStorageDevice(c *gin.Context) *serverutil.Response {
	serial := c.Param("serial")
	if serial == "" {
		return serverutil.BadRequest(errors.New("`serial` path parameter is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	result, err := deviceutil.Enable(deviceutil.EnableParams{
		Storage: deps.StorageService(),
		Serial:  serial,
	})
	if err != nil {
		return deviceError(err)
	}

	return serverutil.Ok().WithData(gin.H{
		"message":    "USB storage device mounted successfully",
		"mount_path": result.MountPath,
		"data_dir":   result.FilesDir,
	})
}

var enableUsbStorageDeviceRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/usb/:serial", enableUsbStorageDevice,
)
