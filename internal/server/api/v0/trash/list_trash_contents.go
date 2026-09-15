package v0_trash

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// listTrashContents godoc
// @Summary List a folder in the trash
// @Description Lists what a trashed folder, or a folder inside one, holds, sorted by name. Each entry's path is relative to the trashed item and can be passed back here, to restore, or to delete. Also returns where the folder would be restored to and when the trashed item expires. A trashed item the caller cannot see is not found.
// @Tags trash
// @Produce json
// @Param serial query string false "Device serial; empty for internal storage"
// @Param trashName query string true "The trashed item"
// @Param path query string false "Path inside the trashed item; empty for the item itself"
// @Success 200 {object} listTrashContentsResponse
// @Failure 400 {object} serverutil.Response "Malformed trash name or path, or not a folder"
// @Failure 404 {object} serverutil.Response "Unknown device, trash name or path"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /trash/contents [get]
func listTrashContents(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	serial := c.Query("serial")
	trashName := c.Query("trashName")

	recorded, err := deps.StorageService().ReadTrashEntry(storageutil.ReadTrashEntryParams{
		DeviceSerial: serial,
		TrashName:    trashName,
	})
	if err != nil {
		return trashError(err)
	}
	if !access.CanSeeTrash(serial, trashName, recorded.Entry.OriginalPath, recorded.Entry.TrashedBy) {
		return serverutil.NotFound(storageutil.ErrTrashItemNotFound)
	}

	result, err := deps.StorageService().ListTrashContents(storageutil.ListTrashContentsParams{
		DeviceSerial: serial,
		TrashName:    trashName,
		Path:         c.Query("path"),
	})
	if err != nil {
		return trashError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(listTrashContentsResponse{
		Items:        result.Items,
		OriginalPath: result.OriginalPath,
		ExpiresAt:    result.ExpiresAt,
	})
}

var listTrashContentsRoute = serverutil.ApiRoute("GET", "/trash/contents", listTrashContents)
