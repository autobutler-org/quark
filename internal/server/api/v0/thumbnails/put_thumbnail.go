package v0_thumbnails

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"

	"github.com/gin-gonic/gin"
)

// errReadOnly is what a caller hears when they may see a file but not attach
// a thumbnail to it.
var errReadOnly = errors.New("you do not have permission to change this")

// putThumbnail godoc
// @Summary Upload a client-rendered thumbnail for a file
// @Description Stores the thumbnail a client rendered for a photo or video, replacing any stored before: a JPEG with a long edge of 400 and rotation applied, in a part named "thumbnail". The sm, md and lg sizes are resized from it, and a photo's thumbnail feeds near-duplicate detection. It lives in the thumbnail cache, so a move, rename or cache clear drops it and a client renders it again on view. Needs write access on the file.
// @Tags thumbnails
// @Accept multipart/form-data
// @Param filePath path string true "Path to the photo or video"
// @Param serial query string false "Device serial number (for device-specific files)"
// @Param thumbnail formData file true "Thumbnail JPEG, long edge 400"
// @Success 204 "No Content"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /thumbnails/{filePath} [put]
func putThumbnail(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	serial := c.Query("serial")
	relPath := strings.TrimPrefix(c.Param("filePath"), "/")

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	check := access.Check(serial, relPath, accessutil.Write)
	if !check.Readable {
		return serverutil.NotFound(fmt.Errorf("file not found: %s", relPath))
	}
	if !check.Allowed {
		return serverutil.Forbidden(errReadOnly)
	}
	reader, err := c.Request.MultipartReader()
	if err != nil {
		return serverutil.BadRequest(err)
	}

	_, err = thumbnailutil.StoreClientThumbnails(thumbnailutil.StoreClientThumbnailsParams{
		Queries: deps.Database().Queries,
		Storage: deps.StorageService(),
		Serial:  serial,
		RelPath: relPath,
		Reader:  reader,
	})
	switch {
	case errors.Is(err, thumbnailutil.ErrSourceNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, thumbnailutil.ErrNotMedia), errors.Is(err, thumbnailutil.ErrNoThumbnail),
		errors.Is(err, thumbnailutil.ErrInvalidThumbnail):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var putThumbnailRoute = serverutil.ApiRoute("PUT", "/thumbnails/*filePath", putThumbnail)
