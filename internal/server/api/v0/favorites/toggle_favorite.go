package v0_favorites

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// toggleFavorite godoc
// @Summary Toggle a photo favorite
// @Description Adds the photo to the caller's own favorites if not already favorited; removes it otherwise. Needs read access on the photo.
// @Tags favorites
// @Accept json
// @Produce json
// @Param body body favoriteRequest true "Photo reference"
// @Success 200 {object} favoriteResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /photos/favorite [post]
func toggleFavorite(c *gin.Context) *serverutil.Response {
	var req favoriteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(errors.New("invalid request body"))
	}
	if req.RelPath == "" {
		return serverutil.BadRequest(errors.New("relPath is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(req.DeviceSerial, req.RelPath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	isFav, err := favoritesutil.ToggleFavorite(
		c.Request.Context(),
		deps.Database().Queries,
		access.Principal().UserID,
		req.DeviceSerial,
		req.RelPath,
	)
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(favoriteResponse{
		IsFavorite: isFav,
	})
}

var toggleFavoriteRoute = serverutil.ApiRoute("POST", "/photos/favorite", toggleFavorite)
