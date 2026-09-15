package v0_trash

import (
	"context"
	"log/slog"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// restoreTrash godoc
// @Summary Restore items from the trash
// @Description Moves trashed items back to where they were deleted from. An item with a path restores only that file or folder from inside a trashed folder, to the folder's original path joined with it, recreating missing parent folders; the trashed folder keeps the rest. Every item is checked first, so a batch naming an unknown item, one whose destination is now occupied, or two whose destinations overlap restores nothing; nothing is ever overwritten.
// @Tags trash
// @Accept json
// @Produce json
// @Param body body trashItemsRequest true "Device serial and the items to restore: a trash name, plus a path inside a trashed folder to restore only that"
// @Success 200 {object} restoreTrashResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "No write access on the folder an item goes back into"
// @Failure 404 {object} serverutil.Response "Unknown device, trash name or path, or an item the caller cannot see"
// @Failure 409 {object} serverutil.Response "Destination occupied or overlapping another in the batch, or original location unknown"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /trash/restore [post]
func restoreTrash(c *gin.Context) *serverutil.Response {
	req, err := bindTrashItems(c.ShouldBindJSON)
	if err != nil {
		return serverutil.BadRequest(err)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	// Every item is checked before any is restored, the way the restore
	// checks the batch itself (#1905).
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
		destination := path.Dir(path.Join(entry.OriginalPath, item.Path))
		if !access.Check(req.Serial, destination, accessutil.Write).Allowed {
			return serverutil.Forbidden(errTrashReadOnly)
		}
	}

	result, err := deps.StorageService().RestoreTrash(storageutil.RestoreTrashParams{
		DeviceSerial: req.Serial,
		Items:        req.Items,
		EventBus:     deps.EventBus(),
	})
	// Access rows come back out with each item, including the ones a failed
	// batch restored before it stopped (#1905).
	for _, item := range result.Restored {
		if _, rowErr := accessutil.MoveRows(accessutil.MoveRowsParams{
			Ctx:       context.WithoutCancel(c.Request.Context()),
			Database:  deps.Database(),
			EventBus:  deps.EventBus(),
			OldSerial: req.Serial,
			OldPath:   item.Source,
			NewSerial: req.Serial,
			NewPath:   item.Path,
		}); rowErr != nil {
			slog.Error("trash: could not carry access rows out of the trash", "from", item.Source, "to", item.Path, "err", rowErr)
		}
	}
	if err != nil {
		return trashError(err)
	}
	paths := make([]string, len(result.Restored))
	for i, item := range result.Restored {
		paths[i] = item.Path
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(restoreTrashResponse{
		RestoredPaths: paths,
	})
}

var restoreTrashRoute = serverutil.ApiRoute("POST", "/trash/restore", restoreTrash)
