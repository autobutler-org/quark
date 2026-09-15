package v0_favorites

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/gin-gonic/gin"
)

// listFavorites godoc
// @Summary List all favorited photos
// @Description Returns the photos the caller has favorited and can still read, newest first. Every account has its own favorites, admins included.
// @Tags favorites
// @Produce json
// @Success 200 {array} favoriteItemJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /photos/favorites [get]
func listFavorites(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	items, err := deps.Database().Queries.ListFavorites(c.Request.Context(), access.Principal().UserID)
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result := make([]favoriteItemJSON, 0, len(items))
	for _, item := range items {
		if !access.Check(item.DeviceSerial, item.RelPath, accessutil.Read).Readable {
			continue
		}
		result = append(result, favoriteItemJSON{
			DeviceSerial: item.DeviceSerial,
			RelPath:      item.RelPath,
			CreatedAt:    sqlutil.FormatTime(item.CreatedAt),
		})
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listFavoritesRoute = serverutil.ApiRoute("GET", "/photos/favorites", listFavorites)
