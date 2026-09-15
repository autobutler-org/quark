package v0_trash

import (
	"context"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// deleteTrash godoc
// @Summary Delete items from the trash permanently
// @Description Deletes the named trashed items for good. An item with a path deletes only that file or folder from inside a trashed folder. Every item is checked first, so a batch naming an unknown item deletes nothing.
// @Tags trash
// @Accept json
// @Produce json
// @Param body body trashItemsRequest true "Device serial and the items to delete: a trash name, plus a path inside a trashed folder to delete only that"
// @Success 200 {object} deletedResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "An item the caller can see but did not trash and cannot write where it came from"
// @Failure 404 {object} serverutil.Response "Unknown device, trash name or path, or an item the caller cannot see"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /trash/delete [post]
func deleteTrash(c *gin.Context) *serverutil.Response {
	req, err := bindTrashItems(c.ShouldBindJSON)
	if err != nil {
		return serverutil.BadRequest(err)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := loadAccess(c, deps)
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	// Deleting for good is for the user who trashed an item, anyone who can
	// write where it came from, and admins (#1905). Every item is checked
	// before any is deleted.
	for _, item := range req.Items {
		recorded, err := deps.StorageService().ReadTrashEntry(storageutil.ReadTrashEntryParams{
			DeviceSerial: req.Serial,
			TrashName:    item.TrashName,
		})
		if err != nil {
			return trashError(err)
		}
		entry := recorded.Entry
		if !access.CanSeeTrash(req.Serial, item.TrashName, entry.OriginalPath, entry.TrashedBy) {
			return serverutil.NotFound(storageutil.ErrTrashItemNotFound)
		}
		if !access.CanDeleteTrash(req.Serial, entry.OriginalPath, entry.TrashedBy) {
			return serverutil.Forbidden(errTrashReadOnly)
		}
	}

	result, err := deps.StorageService().DeleteTrash(storageutil.DeleteTrashParams{
		DeviceSerial: req.Serial,
		Items:        req.Items,
		EventBus:     deps.EventBus(),
	})
	// Rows go with what was deleted for good, so something created at that
	// path later starts with none (#1905).
	if _, rowErr := accessutil.DeleteRows(accessutil.DeleteRowsParams{
		Ctx:          context.WithoutCancel(c.Request.Context()),
		Database:     deps.Database(),
		EventBus:     deps.EventBus(),
		DeviceSerial: req.Serial,
		Paths:        result.Removed,
	}); rowErr != nil {
		slog.Error("trash: could not delete access rows", "paths", result.Removed, "err", rowErr)
	}
	if err != nil {
		return trashError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(deletedResponse{
		Deleted: result.Deleted,
	})
}

var deleteTrashRoute = serverutil.ApiRoute("POST", "/trash/delete", deleteTrash)
