package v0_albums

import (
	"context"
	"database/sql"
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

// listAlbumItems godoc
// @Summary List photos in an album
// @Description Returns the photo items (pointers) the caller can read in one of the caller's albums.
// @Tags albums
// @Produce json
// @Param id path int true "Album ID"
// @Success 200 {array} AlbumItemJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found: no album of the caller's has that id"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /albums/{id}/items [get]
func listAlbumItems(c *gin.Context) *serverutil.Response {
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
	_, err = deps.Database().Queries.GetAlbum(context.Background(), db.GetAlbumParams{ID: id, UserID: access.Principal().UserID})
	if errors.Is(err, sql.ErrNoRows) {
		return serverutil.NotFound(errAlbumNotFound)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	items, err := deps.Database().Queries.ListAlbumItems(context.Background(), id)
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result := make([]AlbumItemJSON, 0, len(items))
	for _, item := range items {
		if !access.Check(item.DeviceSerial, item.RelPath, accessutil.Read).Readable {
			continue
		}
		result = append(result, AlbumItemJSON{
			ID:           item.ID,
			AlbumID:      item.AlbumID,
			DeviceSerial: item.DeviceSerial,
			RelPath:      item.RelPath,
			AddedAt:      sqlutil.FormatTime(item.AddedAt),
		})
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listAlbumItemsRoute = serverutil.ApiRoute(
	"GET", "/albums/:id/items", listAlbumItems,
)
