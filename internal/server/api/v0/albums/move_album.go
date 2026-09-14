package v0_albums

import (
	"context"
	"database/sql"
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// moveAlbum godoc
// @Summary Move a photo album to a new parent
// @Description Changes the parent of an album. Pass null parentId to move to root. The new parent must not already hold an album with the same name ignoring case; root albums, the system Favorites album included, are siblings of each other.
// @Tags albums
// @Accept json
// @Produce json
// @Param id path int true "Album ID"
// @Param body body moveAlbumRequest true "New parent ID (null for root)"
// @Success 200 {object} AlbumJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden: system album, or a system album as the parent"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 409 {object} serverutil.Response "Conflict: an album with that name already exists here"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /albums/{id}/move [patch]
func moveAlbum(c *gin.Context) *serverutil.Response {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(errors.New("invalid album id"))
	}

	var req moveAlbumRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("invalid request body"))
	}

	if req.ParentID != nil && *req.ParentID == id {
		return serverutil.BadRequest(errors.New("album cannot be its own parent"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	if resp := rejectSystemAlbum(c.Request.Context(), deps.Database().Queries, id); resp != nil {
		return resp
	}

	var parentID sql.NullInt64
	if req.ParentID != nil {
		parent, err := deps.Database().Queries.GetAlbum(context.Background(), *req.ParentID)
		if err != nil {
			return serverutil.BadRequest(errors.New("parent album not found"))
		}
		if resp := forbidSystemAlbum(parent); resp != nil {
			return resp
		}
		parentID = sql.NullInt64{Int64: *req.ParentID, Valid: true}
	}

	result, err := albumutil.MoveAlbum(c.Request.Context(), albumutil.MoveAlbumParams{
		Queries:  deps.Database().Queries,
		ID:       id,
		ParentID: parentID,
	})
	if err != nil {
		return albumWriteError(err)
	}

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	count := countItems(deps.Database().Queries, access, result.Album.ID)

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(toAlbumJSON(result.Album, count))
}

var moveAlbumRoute = serverutil.ApiRoute(
	"PATCH", "/albums/:id/move", moveAlbum,
)
