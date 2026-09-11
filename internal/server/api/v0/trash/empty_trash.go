package v0_trash

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// emptyTrash godoc
// @Summary Empty the trash
// @Description Permanently deletes everything in a device's trash.
// @Tags trash
// @Accept json
// @Produce json
// @Param body body emptyTrashRequest true "Device serial; empty for internal storage"
// @Success 200 {object} deletedResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Unknown device"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
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

	result, err := deps.StorageService().EmptyTrash(storageutil.EmptyTrashParams{
		DeviceSerial: req.Serial,
		EventBus:     deps.EventBus(),
	})
	if err != nil {
		return trashError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(deletedResponse{
		Deleted: result.Deleted,
	})
}

var emptyTrashRoute = serverutil.ApiRoute("POST", "/trash/empty", emptyTrash)
