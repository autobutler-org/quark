package v0_thumbnails

import (
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"

	"github.com/gin-gonic/gin"
)

// getThumbnail godoc
// @Summary Get thumbnail for an image
// @Description Generates and returns a thumbnail (resized image) for the specified file
// @Tags thumbnails
// @Produce image/png image/jpeg
// @Param filePath path string true "Path to the image file"
// @Param serial query string false "Device serial number (for device-specific files)"
// @Param size query string false "Thumbnail size tier: sm (96px), md (240px), lg (400px). Defaults to lg." Enums(sm, md, lg)
// @Success 200 {file} file
// @Failure 304 "Not Modified"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /thumbnails/{filePath} [get]
var getThumbnailRoute = serverutil.ApiRoute(
	"GET", "/thumbnails/*filePath", func(c *gin.Context) *serverutil.Response {
		deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
		if !ok {
			return serverutil.InternalServerError(nil)
		}
		filePath := c.Param("filePath")
		serial := c.Query("serial")
		ext := strings.ToLower(filepath.Ext(filePath))
		fileType := storageutil.DetermineFileTypeFromPath("file" + ext)
		if fileType != storageutil.FileTypeImage && fileType != storageutil.FileTypeVideo {
			return serverutil.NotFound(fmt.Errorf("no thumbnail for file type %q: %s", fileType, filePath))
		}
		isVideo := fileType == storageutil.FileTypeVideo

		// relPath strips the leading '/' that the wildcard param includes.
		relPath := strings.TrimPrefix(filePath, "/")

		// The file browser inside an archive asks for /thumbnails/<archive>/<entry>.
		archive, err := fileutil.FindArchive(fileutil.FindArchiveParams{
			Ctx:      c.Request.Context(),
			Registry: deps.VFSRegistry(),
			Storage:  deps.StorageService(),
			FilePath: relPath,
			Serial:   serial,
		})
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		if archive.Found {
			return getArchiveThumbnail(c, deps, archive, ext, filePath, serial, isVideo)
		}

		// VFS path: no-serial, non-RAW, non-video images only.
		// RAW and video need OS paths for external tools (dcraw/ffmpeg).
		if serial == "" && !isVideo && !photoutil.IsRawFile(relPath) {
			if reg := deps.VFSRegistry(); reg != nil {
				if fsys, ok := reg.Get("files"); ok {
					if resp := getThumbnailVFS(c, deps, fsys, relPath, ext, filePath, serial); resp != vfsThumbnailFallthrough {
						return resp
					}
				}
			}
		}

		// StorageService fallback: serial-scoped, RAW, video, or no VFS.
		filesDir, err := storageutil.GetFilesDir()
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		if deviceDir, ok := deps.StorageService().FindDeviceFilesDirBySerial(serial); ok {
			filesDir = deviceDir
		}

		fullPath := filepath.Join(filesDir, filePath)

		srcInfo, err := os.Stat(fullPath)
		if storageutil.IsNotExist(err) {
			return serverutil.NotFound(fmt.Errorf("thumbnail not found: %s", filePath))
		}
		if err != nil {
			return serverutil.InternalServerError(err)
		}

		prepared, err := thumbnailutil.Prepare(thumbnailutil.PrepareParams{
			Queries:    deps.Database().Queries,
			Serial:     serial,
			RelPath:    relPath,
			FilePath:   filePath,
			Size:       thumbnailutil.ParseSize(c.Query("size")),
			SrcModTime: srcInfo.ModTime(),
		})
		if err != nil {
			return serverutil.InternalServerError(err)
		}

		cachedModTime := prepared.CachedModTime
		if !prepared.Hit {
			// Acquire IO semaphore before disk-bound thumbnail generation.
			if sem := deps.IOSemaphore(); sem != nil {
				if !sem.AcquireDefault(c.Request.Context()) {
					slog.Warn("thumbnail: IO semaphore timed out",
						"path", filePath,
						"available", sem.Available(),
						"cap", sem.Cap(),
					)
					c.Header("Retry-After", "5")
					c.JSON(http.StatusServiceUnavailable, gin.H{"error": "server busy, please retry"})
					return nil
				}
				defer sem.Release()
			}

			generated, genErr := thumbnailutil.Generate(thumbnailutil.GenerateParams{
				Ctx:              c.Request.Context(),
				Queries:          deps.Database().Queries,
				Serial:           serial,
				RelPath:          relPath,
				SourcePath:       fullPath,
				Ext:              ext,
				IsVideo:          isVideo,
				Width:            prepared.Width,
				Height:           prepared.Height,
				RotationQuarters: prepared.RotationQuarters,
				CachedPath:       prepared.CachedPath,
			})
			if errors.Is(genErr, thumbnailutil.ErrFFmpegUnavailable) {
				return serverutil.NotFound(genErr)
			}
			if genErr != nil {
				return serverutil.InternalServerError(genErr)
			}
			cachedModTime = generated.CachedModTime
		}

		thumbContentType := thumbnailutil.ContentTypeForExt(ext)
		if isVideo {
			thumbContentType = "image/jpeg"
		}
		return serveCachedThumbnail(c, prepared.CachedPath, cachedModTime, thumbContentType)
	},
)
