package v0_favorites

import (
	"errors"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// isFavorite godoc
// @Summary Check if a photo is favorited
// @Description Returns whether the specified photo is in the user's favorites. Needs read access on the photo.
// @Tags favorites
// @Produce json
// @Param serial query string false "Device serial"
// @Param relPath query string true "Relative path to the photo"
// @Success 200 {object} favoriteResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /photos/favorite [get]
func isFavorite(c *gin.Context) *serverutil.Response {
	relPath := c.Query("relPath")
	if relPath == "" {
		return serverutil.BadRequest(errors.New("relPath is required"))
	}
	serial := c.Query("serial")

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(serial, relPath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	fav, err := deps.Database().Queries.IsFavorite(c.Request.Context(), db.IsFavoriteParams{
		DeviceSerial: serial,
		RelPath:      relPath,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(favoriteResponse{
		IsFavorite: fav,
	})
}

var isFavoriteRoute = serverutil.ApiRoute("GET", "/photos/favorite", isFavorite)
