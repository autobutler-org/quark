package v0_photos

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getMapTile godoc
// @Summary Get a map tile
// @Description Serves one 256-pixel PNG tile of the Quark's own offline map tile pack, a z/x/y.png tree in the data directory, which the Locations view draws its map from by default so no third party learns which area is being looked at. A tile the pack does not hold, or a z/x/y that names no tile, is 404. The request names only the tile, never a photo or a photo's position.
// @Tags photos
// @Produce png
// @Param z path int true "Zoom level, 0 to 19"
// @Param x path int true "Tile column"
// @Param y path int true "Tile row, without the .png extension"
// @Success 200 {file} binary
// @Failure 404 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /photos/map-tiles/{z}/{x}/{y} [get]
func getMapTile(c *gin.Context) *serverutil.Response {
	tile, err := photoutil.OpenMapTile(photoutil.OpenMapTileParams{
		Z: c.Param("z"), X: c.Param("x"), Y: c.Param("y"),
	})
	if errors.Is(err, photoutil.ErrNoMapTile) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	defer func() {
		if err := tile.Reader.Close(); err != nil {
			slog.Warn("photos: closing a map tile failed", "err", err)
		}
	}()
	c.Header("Cache-Control", "private, max-age=86400")
	c.Header("X-Content-Type-Options", "nosniff")
	c.DataFromReader(http.StatusOK, tile.Size, "image/png", tile.Reader, nil)
	return nil
}

var getMapTileRoute = serverutil.ApiRoute("GET", "/photos/map-tiles/:z/:x/:y", getMapTile)
