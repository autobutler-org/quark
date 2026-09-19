package v0_albums

import (
	"context"
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// removePhotoFromAlbum godoc
// @Summary Remove a photo from an album
// @Description Removes the album membership pointer. Does not delete the photo from disk.
// @Tags albums
// @Accept json
// @Produce json
// @Param id path int true "Album ID"
// @Param body body addPhotoRequest true "Photo reference"
// @Success 204 {object} serverutil.Response "No Content"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden: system album"
// @Failure 404 {object} serverutil.Response "Not Found: no album of the caller's has that id"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /albums/{id}/items [delete]
func removePhotoFromAlbum(c *gin.Context) *serverutil.Response {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(errors.New("invalid album id"))
	}

	var req addPhotoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("invalid request body"))
	}
	if req.RelPath == "" {
		return serverutil.BadRequest(errors.New("relPath is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	if resp := rejectSystemAlbum(c.Request.Context(), deps.Database().Queries, callerID(c), id); resp != nil {
		return resp
	}

	if err := deps.Database().Queries.RemovePhotoFromAlbum(context.Background(), db.RemovePhotoFromAlbumParams{
		AlbumID:      id,
		DeviceSerial: req.DeviceSerial,
		RelPath:      req.RelPath,
	}); err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithStatusCode(204)
}

var removePhotoFromAlbumRoute = serverutil.ApiRoute(
	"DELETE", "/albums/:id/items", removePhotoFromAlbum,
)
