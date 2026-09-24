package v0_thumbnails

import (
	"errors"
	"fmt"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"

	"github.com/gin-gonic/gin"
)

// errReadOnly is what a caller hears when they may see a file but not attach
// thumbnails to it.
var errReadOnly = errors.New("you do not have permission to change this")

// putThumbnail godoc
// @Summary Attach client-rendered thumbnails to a file
// @Description Stores the thumbnail, the display preview, or both, that a client rendered for a photo or video, replacing any stored before. The thumbnail is a JPEG with a long edge of 400; the preview, for HEIC and video, a JPEG with a long edge of about 2048. Both have rotation applied. The sm, md and lg sizes are resized from the thumbnail, and a photo's thumbnail feeds near-duplicate detection. Used by clients after a resumable upload or a trim, and by backfill. Needs write access on the file.
// @Tags thumbnails
// @Accept multipart/form-data
// @Produce json
// @Param filePath path string true "Path to the photo or video"
// @Param serial query string false "Device serial number (for device-specific files)"
// @Param thumbnail formData file false "Thumbnail JPEG, long edge 400"
// @Param preview formData file false "Display preview JPEG, long edge about 2048"
// @Success 200 {object} putThumbnailResponse "OK"
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

	result, err := thumbnailutil.StoreDerivatives(thumbnailutil.StoreDerivativesParams{
		Queries:  deps.Database().Queries,
		Storage:  deps.StorageService(),
		EventBus: deps.EventBus(),
		Serial:   serial,
		RelPath:  relPath,
		Reader:   reader,
	})
	switch {
	case errors.Is(err, thumbnailutil.ErrSourceNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, thumbnailutil.ErrNotMedia), errors.Is(err, thumbnailutil.ErrNoDerivatives),
		errors.Is(err, derivativeutil.ErrInvalid):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	stored := make([]string, len(result.Stored))
	for i, kind := range result.Stored {
		stored[i] = string(kind)
	}
	return serverutil.Ok().WithData(putThumbnailResponse{Stored: stored})
}

var putThumbnailRoute = serverutil.ApiRoute("PUT", "/thumbnails/*filePath", putThumbnail)
