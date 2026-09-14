package v0_albums

import (
	"context"
	"database/sql"
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"

	"github.com/gin-gonic/gin"
)

// getAlbum godoc
// @Summary Get a photo album by ID
// @Description Returns a single album with its item count and direct children.
// @Tags albums
// @Produce json
// @Param id path int true "Album ID"
// @Success 200 {object} AlbumJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /albums/{id} [get]
func getAlbum(c *gin.Context) *serverutil.Response {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(errors.New("invalid album id"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	album, err := deps.Database().Queries.GetAlbum(context.Background(), id)
	if err != nil {
		return serverutil.NotFound(err)
	}

	count := countItems(deps.Database().Queries, access, id)

	children, _ := deps.Database().Queries.ListChildAlbums(context.Background(), sql.NullInt64{Int64: album.ID, Valid: true})
	childJSON := make([]AlbumJSON, 0, len(children))
	for _, ch := range children {
		chCount := countItems(deps.Database().Queries, access, ch.ID)
		var chParentID *int64
		if ch.ParentID.Valid {
			chParentID = &ch.ParentID.Int64
		}
		childJSON = append(childJSON, AlbumJSON{
			ID:        ch.ID,
			Name:      ch.Name,
			ParentID:  chParentID,
			SmartType: sqlutil.NullStringPtr(ch.SmartType),
			CreatedAt: sqlutil.FormatTime(ch.CreatedAt),
			UpdatedAt: sqlutil.FormatTime(ch.UpdatedAt),
			ItemCount: chCount,
		})
	}

	var parentID *int64
	if album.ParentID.Valid {
		parentID = &album.ParentID.Int64
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(AlbumJSON{
		ID:        album.ID,
		Name:      album.Name,
		ParentID:  parentID,
		SmartType: sqlutil.NullStringPtr(album.SmartType),
		CreatedAt: sqlutil.FormatTime(album.CreatedAt),
		UpdatedAt: sqlutil.FormatTime(album.UpdatedAt),
		ItemCount: count,
		Children:  childJSON,
	})
}

var getAlbumRoute = serverutil.ApiRoute(
	"GET", "/albums/:id", getAlbum,
)
