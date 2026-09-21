package v0_albums

import (
	"context"
	"database/sql"
	"errors"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// createAlbum godoc
// @Summary Create a photo album
// @Description Creates a photo album owned by the caller, optionally nested under one of the caller's albums. The name cannot contain / and must be unique among its siblings ignoring case; the caller's root albums, their Favorites album included, are siblings of each other.
// @Tags albums
// @Accept json
// @Produce json
// @Param body body createAlbumRequest true "Album name and optional parent ID"
// @Success 201 {object} AlbumJSON
// @Failure 400 {object} serverutil.Response "Bad Request: missing name, a / in the name, or parent not found among the caller's albums"
// @Failure 403 {object} serverutil.Response "Forbidden: system album as the parent"
// @Failure 409 {object} serverutil.Response "Conflict: an album with that name already exists here"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /albums [post]
func createAlbum(c *gin.Context) *serverutil.Response {
	var req createAlbumRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("name is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	userID := callerID(c)
	var parentID sql.NullInt64
	if req.ParentID != nil {
		parent, err := deps.Database().Queries.GetAlbum(context.Background(), db.GetAlbumParams{ID: *req.ParentID, UserID: userID})
		if err != nil {
			return serverutil.BadRequest(errors.New("parent album not found"))
		}
		if resp := forbidSystemAlbum(parent); resp != nil {
			return resp
		}
		parentID = sql.NullInt64{Int64: *req.ParentID, Valid: true}
	}

	result, err := albumutil.CreateAlbum(c.Request.Context(), albumutil.CreateAlbumParams{
		Queries:  deps.Database().Queries,
		UserID:   userID,
		Name:     req.Name,
		ParentID: parentID,
	})
	if err != nil {
		return albumWriteError(err)
	}

	return serverutil.Ok().WithStatusCode(201).WithContentType(serverutil.ContentTypeJSON).WithData(toAlbumJSON(result.Album, 0))
}

var createAlbumRoute = serverutil.ApiRoute(
	"POST", "/albums", createAlbum,
)
