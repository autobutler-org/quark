package v0_photos

import (
	"context"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// rotatePhoto godoc
// @Summary Save the rotation for a photo
// @Description Persists the viewer rotation (0/1/2/3 × 90° CW) for a photo server-side. Needs write access on the photo.
// @Tags photos
// @Accept json
// @Produce json
// @Param body body rotatePhotoRequest true "Rotation request"
// @Success 200 {object} serverutil.Response
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
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

	// Rotation describes the file, so everyone who can see it sees it turned,
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

	if err := photoutil.SaveRotation(photoutil.SaveRotationParams{
		Ctx:              context.Background(),
		Queries:          deps.Database().Queries,
		Serial:           req.Serial,
		RelPath:          req.RelPath,
		RotationQuarters: req.RotationQuarters,
	}); err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok()
}

var rotatePhotoRoute = serverutil.ApiRoute("POST", "/photos/rotate", rotatePhoto)
