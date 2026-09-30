package v0_albums

import (
	"context"
	"database/sql"
	"errors"
	"strconv"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
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
// @Param sort query string false "Sort field: added (date added), taken (date taken) or name (default added)"
// @Param order query string false "Sort order: asc or desc (default desc)"
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
	listResult, err := albumutil.ListItems(context.Background(), albumutil.ListItemsParams{
		Queries: deps.Database().Queries,
		Access:  access,
		AlbumID: id,
		Sort:    photoutil.ParseSort(c.Query("sort")),
		Order:   photoutil.ParseOrder(c.Query("order")),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result := make([]AlbumItemJSON, 0, len(listResult.Items))
	for _, item := range listResult.Items {
		result = append(result, AlbumItemJSON{
			ID:           item.ID,
			AlbumID:      item.AlbumID,
			DeviceSerial: item.DeviceSerial,
			RelPath:      item.RelPath,
			AddedAt:      sqlutil.FormatTime(item.AddedAt),
			TakenAt:      takenAt(listResult.TakenAt, item.ID),
		})
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listAlbumItemsRoute = serverutil.ApiRoute(
	"GET", "/albums/:id/items", listAlbumItems,
)
