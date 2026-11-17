package v0_photos

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listLocations godoc
// @Summary List where photos were taken
// @Description Returns every photo the caller can read that has a GPS position in its EXIF data, for the Locations view's map, newest first. Positions come only from each photo's own EXIF, read by the library index; a photo with no position, or a 0,0 one, is never placed. total counts the caller's photos and videos, located those placed, unlocated the rest, and pending those among the rest whose EXIF the index has not read yet. A photo the caller cannot read is neither placed nor counted.
// @Tags photos
// @Produce json
// @Param serial query string false "Restrict to one device"
// @Success 200 {object} photoutil.LocationsResult
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /photos/locations [get]
func listLocations(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	result, err := photoutil.Locations(photoutil.LocationsParams{List: photoutil.ListPhotosParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Serial:   c.Query("serial"),
		Access:   access,
		Queries:  deps.Database().Queries,
		Index:    deps.FileIndex(),
	}})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var listLocationsRoute = serverutil.ApiRoute("GET", "/photos/locations", listLocations)
