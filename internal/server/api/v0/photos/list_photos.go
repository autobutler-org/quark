package v0_photos

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	"github.com/gin-gonic/gin"
)

// PaginatedPhotosResponse wraps a page of photos with pagination metadata.
type PaginatedPhotosResponse struct {
	Photos []photoutil.PhotoSummary `json:"photos"`
	Total  int                      `json:"total"`
	Offset int                      `json:"offset"`
	Limit  int                      `json:"limit"`
}

// listPhotos godoc
// @Summary List photos
// @Description Finds all photos across all managed devices with pagination support.
// @Tags photos
// @Produce json
// @Param offset query int false "Pagination offset (default 0)"
// @Param limit query int false "Page size (default 50, max 200)"
// @Param serial query string false "Device serial to filter by"
// @Success 200 {object} PaginatedPhotosResponse
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /photos [get]
func listPhotos(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	offset, limit := photoutil.ParsePagination(c.Query("offset"), c.Query("limit"))
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	// VFS path when the registry has the files namespace, walking the managed
	// devices otherwise.
	var fsys vfs.VFS
	if reg := deps.VFSRegistry(); reg != nil {
		if registered, found := reg.Get("files"); found {
			fsys = registered
		}
	}

	result, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
		Ctx:     c.Request.Context(),
		FS:      fsys,
		Storage: deps.StorageService(),
		Serial:  c.Query("serial"),
		Access:  access,
		Offset:  offset,
		Limit:   limit,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(PaginatedPhotosResponse{
		Photos: result.Photos,
		Total:  result.Total,
		Offset: result.Offset,
		Limit:  result.Limit,
	})
}

var listPhotosRoute = serverutil.ApiRoute(
	"GET", "/photos", listPhotos,
)
