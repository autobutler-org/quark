package v0_albums

import (
	"context"
	"database/sql"
	"errors"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"

	"github.com/gin-gonic/gin"
)

// createAlbum godoc
// @Summary Create a photo album
// @Description Creates a new photo album, optionally nested under a parent.
// @Tags albums
// @Accept json
// @Produce json
// @Param body body createAlbumRequest true "Album name and optional parent ID"
// @Success 201 {object} AlbumJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden: system album as the parent"
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

	album, err := deps.Database().Queries.CreateAlbum(context.Background(), db.CreateAlbumParams{
		Name:     req.Name,
		ParentID: parentID,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	var respParentID *int64
	if album.ParentID.Valid {
		respParentID = &album.ParentID.Int64
	}

	return serverutil.Ok().WithStatusCode(201).WithContentType(serverutil.ContentTypeJSON).WithData(AlbumJSON{
		ID:        album.ID,
		Name:      album.Name,
		ParentID:  respParentID,
		SmartType: sqlutil.NullStringPtr(album.SmartType),
		CreatedAt: sqlutil.FormatTime(album.CreatedAt),
		UpdatedAt: sqlutil.FormatTime(album.UpdatedAt),
		ItemCount: 0,
	})
}

var createAlbumRoute = serverutil.ApiRoute(
	"POST", "/albums", createAlbum,
)
