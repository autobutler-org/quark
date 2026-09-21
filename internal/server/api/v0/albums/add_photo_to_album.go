package v0_albums

import (
	"context"
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"

	"github.com/gin-gonic/gin"
)

// addPhotoToAlbum godoc
// @Summary Add a photo to an album
// @Description Adds a photo (by device serial + relative path) to an album. Idempotent. Needs read access on the photo.
// @Tags albums
// @Accept json
// @Produce json
// @Param id path int true "Album ID"
// @Param body body addPhotoRequest true "Photo reference"
// @Success 201 {object} AlbumItemJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden: system album"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /albums/{id}/items [post]
func addPhotoToAlbum(c *gin.Context) *serverutil.Response {
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

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(req.DeviceSerial, req.RelPath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	album, err := deps.Database().Queries.GetAlbum(context.Background(), db.GetAlbumParams{ID: id, UserID: callerID(c)})
	if err != nil {
		return serverutil.NotFound(errAlbumNotFound)
	}
	if resp := forbidSystemAlbum(album); resp != nil {
		return resp
	}

	item, err := deps.Database().Queries.AddPhotoToAlbum(context.Background(), db.AddPhotoToAlbumParams{
		AlbumID:      id,
		DeviceSerial: req.DeviceSerial,
		RelPath:      req.RelPath,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithStatusCode(201).WithContentType(serverutil.ContentTypeJSON).WithData(AlbumItemJSON{
		ID:           item.ID,
		AlbumID:      item.AlbumID,
		DeviceSerial: item.DeviceSerial,
		RelPath:      item.RelPath,
		AddedAt:      sqlutil.FormatTime(item.AddedAt),
	})
}

var addPhotoToAlbumRoute = serverutil.ApiRoute(
	"POST", "/albums/:id/items", addPhotoToAlbum,
)
