package v0_trash

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// listTrash godoc
// @Summary List the trash
// @Description Lists a device's trashed items, most recently trashed first, with how many days anything stays before the hourly purge deletes it. A non-admin sees what they trashed and what was trashed from a place they can read.
// @Tags trash
// @Produce json
// @Param serial query string false "Device serial; empty for internal storage"
// @Success 200 {object} listTrashResponse
// @Failure 404 {object} serverutil.Response "Unknown device"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /trash [get]
func listTrash(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	serial := c.Query("serial")

	result, err := deps.StorageService().ListTrash(storageutil.ListTrashParams{
		DeviceSerial: serial,
	})
	if err != nil {
		return trashError(err)
	}
	visible := accessutil.VisibleTrash(accessutil.VisibleTrashParams{
		Access:       access,
		DeviceSerial: serial,
		Items:        result.Items,
	})
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(listTrashResponse{
		RetentionDays: storageutil.TrashRetentionDays,
		Items:         visible.Items,
	})
}

var listTrashRoute = serverutil.ApiRoute("GET", "/trash", listTrash)
