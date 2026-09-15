package v0_albums

import (
	"context"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"

	"github.com/gin-gonic/gin"
)

// listAlbums godoc
// @Summary List all photo albums
// @Description Returns all photo albums as a flat list. Use ?tree=true to get a nested tree.
// @Tags albums
// @Produce json
// @Param tree query bool false "Return as nested tree (default false)"
// @Success 200 {array} AlbumJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /albums [get]
func listAlbums(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	// Each account's Favorites album is created the first time it lists its
	// albums. A failure only leaves it out of this listing.
	if _, err := favoritesutil.EnsureFavoritesAlbum(c.Request.Context(), deps.Database().Queries, access.Principal().UserID); err != nil {
		_ = c.Error(err)
	}
	albums, err := deps.Database().Queries.ListAlbums(context.Background())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result := make([]AlbumJSON, 0, len(albums))
	for _, a := range albums {
		count := countItems(deps.Database().Queries, access, a.ID)
		var parentID *int64
		if a.ParentID.Valid {
			parentID = &a.ParentID.Int64
		}
		result = append(result, AlbumJSON{
			ID:        a.ID,
			Name:      a.Name,
			ParentID:  parentID,
			SmartType: sqlutil.NullStringPtr(a.SmartType),
			CreatedAt: sqlutil.FormatTime(a.CreatedAt),
			UpdatedAt: sqlutil.FormatTime(a.UpdatedAt),
			ItemCount: count,
		})
	}

	wantTree := c.Query("tree") == "true"
	if wantTree {
		return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(buildTree(result))
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listAlbumsRoute = serverutil.ApiRoute(
	"GET", "/albums", listAlbums,
)
