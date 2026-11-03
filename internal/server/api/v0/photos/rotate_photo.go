package v0_photos

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// rotatePhoto godoc
// @Summary Turn a photo
// @Description Turns a JPEG by the given number of clockwise quarter turns by rewriting its EXIF Orientation tag, so no pixels are re-encoded. Other formats are refused with 422. Needs write access on the photo.
// @Tags photos
// @Accept json
// @Produce json
// @Param body body rotatePhotoRequest true "Rotation request"
// @Success 200 {object} rotatePhotoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 422 {object} serverutil.Response "Rotation not supported for this format"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /photos/rotate [post]
func rotatePhoto(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req rotatePhotoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	// Rotation changes the file, so everyone who can see it sees it turned,
	// and only someone who can change the file may turn it (#1904).
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	check := access.Check(req.Serial, req.RelPath, accessutil.Write)
	if !check.Readable {
		return serverutil.NotFound(errNoAccess)
	}
	if !check.Allowed {
		return serverutil.Forbidden(errReadOnly)
	}

	result, err := photoutil.RotatePhoto(photoutil.RotatePhotoParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		EventBus: deps.EventBus(),
		Serial:   req.Serial,
		RelPath:  req.RelPath,
		Quarters: req.Quarters,
	})
	switch {
	case errors.Is(err, photoutil.ErrRotationUnsupported):
		return serverutil.NewResponse().WithStatusCode(http.StatusUnprocessableEntity).WithError(err)
	case errors.Is(err, vfs.ErrNotFound):
		return serverutil.NotFound(fmt.Errorf("photo not found: %s", req.RelPath))
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().
		WithContentType(serverutil.ContentTypeJSON).
		WithData(rotatePhotoResponse{Orientation: result.Orientation})
}

var rotatePhotoRoute = serverutil.ApiRoute("POST", "/photos/rotate", rotatePhoto)
