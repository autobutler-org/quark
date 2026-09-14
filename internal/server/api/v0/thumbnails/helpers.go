package v0_thumbnails

import (
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// getArchiveThumbnail serves the thumbnail of an image inside an archive. An
// entry is only a stream, so RAW and video entries, whose thumbnails need an
// OS path for an external tool, get none, and neither does an entry that will
// not decode or is too large to hold in memory. Each of those is a 404, which
// the client shows as the file icon.
func getArchiveThumbnail(
	c *gin.Context,
	deps deputil.Dependencies,
	archive fileutil.FindArchiveResult,
	ext, filePath, serial string,
	isVideo bool,
) *serverutil.Response {
	if isVideo || photoutil.IsRawFile(archive.EntryPath) {
		return serverutil.NotFound(fmt.Errorf("no thumbnail for archive entry: %s", filePath))
	}

	prepared, err := thumbnailutil.Prepare(thumbnailutil.PrepareParams{
		Queries:    deps.Database().Queries,
		Serial:     serial,
		RelPath:    strings.TrimPrefix(filePath, "/"),
		FilePath:   filePath,
		Size:       thumbnailutil.ParseSize(c.Query("size")),
		SrcModTime: archive.ModTime,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	cachedModTime := prepared.CachedModTime
	if !prepared.Hit {
		if sem := deps.IOSemaphore(); sem != nil {
			if !sem.AcquireDefault(c.Request.Context()) {
				slog.Warn("thumbnail: IO semaphore timed out (archive entry)",
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

		entry, err := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
			Ctx:         c.Request.Context(),
			Registry:    deps.VFSRegistry(),
			Storage:     deps.StorageService(),
			ArchivePath: archive.ArchivePath,
			EntryPath:   archive.EntryPath,
			Serial:      serial,
		})
		var notFound *fileutil.NotFoundError
		if errors.As(err, &notFound) {
			return serverutil.NotFound(err)
		}
		if err != nil {
			return serverutil.InternalServerError(err)
		}
		defer entry.Reader.Close()

		// The declared size turns away an honest oversized entry; the
		// LimitReader truncates a lying header, which then fails to decode.
		if entry.Size > thumbnailutil.MaxBufferedSourceBytes {
			return serverutil.NotFound(fmt.Errorf("archive entry too large for a thumbnail: %s", filePath))
		}
		generated, genErr := thumbnailutil.GenerateFromReader(thumbnailutil.GenerateFromReaderParams{
			Reader:           io.LimitReader(entry.Reader, thumbnailutil.MaxBufferedSourceBytes),
			Ext:              ext,
			Width:            prepared.Width,
			Height:           prepared.Height,
			RotationQuarters: prepared.RotationQuarters,
			CachedPath:       prepared.CachedPath,
		})
		if errors.Is(genErr, thumbnailutil.ErrUnsupportedSource) {
			return serverutil.NotFound(genErr)
		}
		if genErr != nil {
			return serverutil.InternalServerError(genErr)
		}
		cachedModTime = generated.CachedModTime
	}

	return serveCachedThumbnail(c, prepared.CachedPath, cachedModTime, thumbnailutil.ContentTypeForExt(ext))
}

// vfsThumbnailFallthrough is a sentinel returned by getThumbnailVFS to signal
// that the VFS path could not serve the thumbnail and the caller should fall
// through to the StorageService path.
var vfsThumbnailFallthrough = &serverutil.Response{}

// getThumbnailVFS attempts to serve a thumbnail via the VFS. Returns
// vfsThumbnailFallthrough if the VFS is unable to handle the request (file not
// found, unsupported type, etc.) so the caller can use the StorageService path.
func getThumbnailVFS(
	c *gin.Context,
	deps deputil.Dependencies,
	fsys vfs.VFS,
	relPath, ext, filePath, serial string,
) *serverutil.Response {
	ctx := c.Request.Context()

	fi, err := fsys.Stat(ctx, relPath)
	if err != nil {
		// File not accessible via VFS — fall through.
		return vfsThumbnailFallthrough
	}

	prepared, err := thumbnailutil.Prepare(thumbnailutil.PrepareParams{
		Queries:    deps.Database().Queries,
		Serial:     serial,
		RelPath:    relPath,
		FilePath:   filePath,
		Size:       thumbnailutil.ParseSize(c.Query("size")),
		SrcModTime: fi.ModTime,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	cachedModTime := prepared.CachedModTime
	if !prepared.Hit {
		if sem := deps.IOSemaphore(); sem != nil {
			if !sem.AcquireDefault(c.Request.Context()) {
				slog.Warn("thumbnail: IO semaphore timed out (VFS path)",
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

		r, openErr := fsys.Open(ctx, relPath)
		if openErr != nil {
			return vfsThumbnailFallthrough
		}
		defer r.Close()

		generated, genErr := thumbnailutil.GenerateFromReader(thumbnailutil.GenerateFromReaderParams{
			Reader:           r,
			Ext:              ext,
			Width:            prepared.Width,
			Height:           prepared.Height,
			RotationQuarters: prepared.RotationQuarters,
			CachedPath:       prepared.CachedPath,
		})
		if errors.Is(genErr, thumbnailutil.ErrUnsupportedSource) {
			// Unsupported format or decode error — fall through to StorageService.
			return vfsThumbnailFallthrough
		}
		if genErr != nil {
			return serverutil.InternalServerError(genErr)
		}
		cachedModTime = generated.CachedModTime
	}

	return serveCachedThumbnail(c, prepared.CachedPath, cachedModTime, thumbnailutil.ContentTypeForExt(ext))
}

// serveCachedThumbnail writes the caching headers for a cache entry and either
// answers a matching If-None-Match with 304 or sends the cached bytes.
func serveCachedThumbnail(c *gin.Context, cachedPath string, cachedModTime time.Time, contentType string) *serverutil.Response {
	etag := thumbnailutil.ETagFromModTime(cachedModTime)
	c.Header("ETag", etag)
	// no-cache: the browser must revalidate every request via If-None-Match.
	// The ETag covers rotation state (cache key includes rotationQuarters),
	// so the browser gets fresh bytes immediately after a rotation without
	// waiting for a max-age window to expire.
	c.Header("Cache-Control", "no-cache")
	c.Header("Content-Type", contentType)

	if match := c.GetHeader("If-None-Match"); match == etag {
		c.Status(http.StatusNotModified)
		return nil
	}

	f, err := thumbnailutil.OpenCached(cachedPath)
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	defer f.Close()

	// ServeContent streams the entry and fills in Content-Length and range
	// handling. The Content-Type set above stands: an empty name leaves
	// ServeContent nothing to sniff from.
	http.ServeContent(c.Writer, c.Request, "", cachedModTime, f)
	return nil
}
