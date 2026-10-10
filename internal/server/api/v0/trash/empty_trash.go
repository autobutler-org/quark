package v0_trash

import (
	"context"
	"errors"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/trashutil"
	"github.com/gin-gonic/gin"
)

// emptyTrash godoc
// @Summary Empty the trash
// @Description Permanently deletes everything in a device's trash. A non-admin empties only the items they could delete one at a time: the ones they trashed and the ones trashed from a folder they can write.
// @Tags trash
// @Accept json
// @Produce json
// @Param body body emptyTrashRequest true "Device serial; empty for internal storage"
// @Success 200 {object} deletedResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Unknown device"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /trash/empty [post]
func emptyTrash(c *gin.Context) *serverutil.Response {
	var req emptyTrashRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("invalid request body"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	device := trashDevice(c, deps, req.Serial)
	var deleted int
	var removed []string
	var emptyErr error
	if access.Principal().IsAdmin {
		result, err := trashutil.Empty(trashutil.EmptyParams{
			Device:   device,
			EventBus: deps.EventBus(),
		})
		deleted, removed, emptyErr = result.Deleted, result.Removed, err
	} else {
		// A non-admin empties only what they could delete one item at a time
		// (#1905); everyone else's items stay.
		listed, err := trashutil.List(trashutil.ListParams{Device: device})
		if err != nil {
			return trashError(err)
		}
		refs := make([]storageutil.TrashRef, 0, len(listed.Items))
		for _, item := range listed.Items {
			if access.CanSeeTrash(req.Serial, item.TrashName, item.OriginalPath, item.TrashedBy) &&
				access.CanDeleteTrash(req.Serial, item.OriginalPath, item.TrashedBy) {
				refs = append(refs, storageutil.TrashRef{TrashName: item.TrashName})
			}
		}
		if len(refs) > 0 {
			result, err := trashutil.Delete(trashutil.DeleteParams{
				Device:   device,
				Items:    refs,
				EventBus: deps.EventBus(),
			})
			deleted, removed, emptyErr = result.Deleted, result.Removed, err
		}
	}

	if _, rowErr := accessutil.DeleteRows(accessutil.DeleteRowsParams{
		Ctx:          context.WithoutCancel(c.Request.Context()),
		Database:     deps.Database(),
		EventBus:     deps.EventBus(),
		DeviceSerial: req.Serial,
		Paths:        removed,
	}); rowErr != nil {
		slog.Error("trash: could not delete access rows", "paths", removed, "err", rowErr)
	}
	if emptyErr != nil {
		return trashError(emptyErr)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(deletedResponse{
		Deleted: deleted,
	})
}

var emptyTrashRoute = serverutil.ApiRoute("POST", "/trash/empty", emptyTrash)
