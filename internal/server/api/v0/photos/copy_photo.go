package v0_photos

import (
	"errors"
	"fmt"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// copyPhoto godoc
// @Summary Duplicate a photo file
// @Description Creates a copy of the photo in the same directory with a non-conflicting name (e.g. photo_copy.jpg). Needs read access on the photo and write access on its folder; the caller owns the copy.
// @Tags photos
// @Accept json
// @Produce json
// @Param body body copyPhotoRequest true "Copy request"
// @Success 200 {object} copyPhotoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /photos/copy [post]
func copyPhoto(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req copyPhotoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	// The copy lands beside the original, so it needs read on the photo and
	// write on its folder. Both writers pick a name nothing had, so the copy is
	// always new and its owner row never lands on an existing file (#1904).
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(req.Serial, req.RelPath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}
	if !access.Check(req.Serial, path.Dir(accessutil.Canonical(req.RelPath)), accessutil.Write).Allowed {
		return serverutil.Forbidden(errReadOnly)
	}

	// VFS path: no-serial copies go through VFS.Open + VFS.Write.
	if req.Serial == "" {
		if reg := deps.VFSRegistry(); reg != nil {
			if fsys, ok := reg.Get("files"); ok {
				newRelPath, err := photoutil.CopyPhotoVFS(c.Request.Context(), fsys, req.RelPath)
				if err != nil {
					if errors.Is(err, vfs.ErrNotFound) {
						return serverutil.NotFound(fmt.Errorf("photo not found: %s", req.RelPath))
					}
					return serverutil.InternalServerError(err)
				}
				grantOwner(c, deps, access, req.Serial, newRelPath)
				return serverutil.Ok().
					WithContentType(serverutil.ContentTypeJSON).
					WithData(copyPhotoResponse{RelPath: newRelPath})
			}
		}
	}

	// Fallback: StorageService.CopyFile for serial-scoped or non-VFS case.
	result, err := deps.StorageService().CopyFile(storageutil.CopyFileParams{
		RelPath:      req.RelPath,
		DeviceSerial: req.Serial,
	})
	if err != nil {
		if errors.Is(err, storageutil.ErrPathNotFound) {
			return serverutil.NotFound(fmt.Errorf("photo not found: %s", req.RelPath))
		}
		return serverutil.InternalServerError(err)
	}
	grantOwner(c, deps, access, req.Serial, result.NewRelPath)

	return serverutil.Ok().
		WithContentType(serverutil.ContentTypeJSON).
		WithData(copyPhotoResponse{RelPath: result.NewRelPath})
}

var copyPhotoRoute = serverutil.ApiRoute("POST", "/photos/copy", copyPhoto)
