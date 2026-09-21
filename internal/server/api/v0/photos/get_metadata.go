package v0_photos

import (
	"errors"
	"fmt"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// PhotoMetadataJSON is the full metadata response for a single photo.
type PhotoMetadataJSON struct {
	FileName           string                 `json:"fileName"`
	FileSize           int64                  `json:"fileSize"`
	MTime              int64                  `json:"mtime"`
	Width              int                    `json:"width"`
	Height             int                    `json:"height"`
	RotationQuarters   int64                  `json:"rotationQuarters"`
	IsFavorite         bool                   `json:"isFavorite"`
	Exif               *photoutil.ExifSummary `json:"exif,omitempty"`
	Albums             []photoutil.AlbumRef   `json:"albums"`
	LivePhotoVideoPath string                 `json:"livePhotoVideoPath,omitempty"`
}

// getMetadata godoc
// @Summary Get metadata for a single photo
// @Description Returns EXIF, file info, and the caller's own favorite state and album membership for the specified photo.
// @Tags photos
// @Produce json
// @Param serial query string false "Device serial"
// @Param relPath query string true "Relative path to the photo file"
// @Success 200 {object} PhotoMetadataJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /photos/metadata [get]
func getMetadata(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	relPath := c.Query("relPath")
	if relPath == "" {
		return serverutil.BadRequest(fmt.Errorf("relPath is required"))
	}
	serial := c.Query("serial")

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(serial, relPath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	// Stat and EXIF: use VFS when available, fall back to direct disk access.
	var fsys vfs.VFS
	if reg := deps.VFSRegistry(); reg != nil {
		if registered, found := reg.Get("files"); found {
			fsys = registered
		}
	}

	result, err := photoutil.Metadata(photoutil.MetadataParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  access.Principal().UserID,
		Storage: deps.StorageService(),
		FS:      fsys,
		Serial:  serial,
		RelPath: relPath,
	})
	if err != nil {
		switch {
		case errors.Is(err, storageutil.ErrPathNotFound):
			return serverutil.NotFound(fmt.Errorf("photo not found: %s", relPath))
		case errors.Is(err, photoutil.ErrInvalidRelPath):
			return serverutil.BadRequest(fmt.Errorf("invalid relPath"))
		default:
			return serverutil.InternalServerError(err)
		}
	}
	for _, softErr := range result.SoftErrors {
		_ = c.Error(softErr)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(PhotoMetadataJSON{
		FileName:           filepath.Base(relPath),
		FileSize:           result.FileSize,
		MTime:              result.MTime,
		Width:              result.Width,
		Height:             result.Height,
		RotationQuarters:   result.RotationQuarters,
		IsFavorite:         result.IsFavorite,
		Exif:               result.Exif,
		Albums:             result.Albums,
		LivePhotoVideoPath: result.LivePhotoVideoPath,
	})
}

var getMetadataRoute = serverutil.ApiRoute(
	"GET", "/photos/metadata", getMetadata,
)
