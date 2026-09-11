package v0_trash

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// listTrash godoc
// @Summary List the trash
// @Description Lists a device's trashed items, most recently trashed first, with how many days anything stays before the hourly purge deletes it.
// @Tags trash
// @Produce json
// @Param serial query string false "Device serial; empty for internal storage"
// @Success 200 {object} listTrashResponse
// @Failure 404 {object} serverutil.Response "Unknown device"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /trash [get]
func listTrash(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	result, err := deps.StorageService().ListTrash(storageutil.ListTrashParams{
		DeviceSerial: c.Query("serial"),
	})
	if err != nil {
		return trashError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(listTrashResponse{
		RetentionDays: storageutil.TrashRetentionDays,
		Items:         result.Items,
	})
}

var listTrashRoute = serverutil.ApiRoute("GET", "/trash", listTrash)
