package v0_albums

import (
	"context"
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"

	"github.com/gin-gonic/gin"
)

// renameAlbum godoc
// @Summary Rename a photo album
// @Description Updates the name of an existing album.
// @Tags albums
// @Accept json
// @Produce json
// @Param id path int true "Album ID"
// @Param body body renameAlbumRequest true "New album name"
// @Success 200 {object} AlbumJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden: system album"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /albums/{id}/rename [patch]
func renameAlbum(c *gin.Context) *serverutil.Response {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(errors.New("invalid album id"))
	}

	var req renameAlbumRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("name is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	if resp := rejectSystemAlbum(c.Request.Context(), deps.Database().Queries, id); resp != nil {
		return resp
	}

	album, err := deps.Database().Queries.RenameAlbum(context.Background(), db.RenameAlbumParams{
		Name: req.Name,
		ID:   id,
	})
	if err != nil {
		return serverutil.NotFound(err)
	}

	var parentID *int64
	if album.ParentID.Valid {
		parentID = &album.ParentID.Int64
	}

	count, _ := deps.Database().Queries.CountAlbumItems(context.Background(), album.ID)

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(AlbumJSON{
		ID:        album.ID,
		Name:      album.Name,
		ParentID:  parentID,
		SmartType: sqlutil.NullStringPtr(album.SmartType),
		CreatedAt: sqlutil.FormatTime(album.CreatedAt),
		UpdatedAt: sqlutil.FormatTime(album.UpdatedAt),
		ItemCount: count,
	})
}

var renameAlbumRoute = serverutil.ApiRoute(
	"PATCH", "/albums/:id/rename", renameAlbum,
)
