package v0_files

import (
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// downloadFile godoc
// @Summary Download a file or folder
// @Description Downloads a single file or zips a folder and streams it back to the client
// @Tags files
// @Produce application/octet-stream
// @Param filePath query string false "File path to download"
// @Param serial query string false "Device serial number to filter by"
// @Param format query string false "Output format conversion (e.g. 'jpeg' to convert HEIC to JPEG)"
// @Success 200 {file} file
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/download [get]
func downloadFile(c *gin.Context) *serverutil.Response {
	filePath := c.Query("filePath")
	serial := c.Query("serial")
	wantsJPEG := c.Query("format") == "jpeg"

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(serial, filePath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	// Every branch below serves file content under a URL whose only variable is
	// the path, so an edited file reuses the URL its previous contents were
	// served under. http.ServeContent and c.File both send Last-Modified and no
	// Cache-Control, which lets a browser apply heuristic freshness (RFC 9111
	// §4.2.2) and serve the stale body without asking: a .qsheet saved from the
	// editor reopened showing its pre-save contents.
	//
	// no-cache, not no-store — the response may still be stored, it just has to
	// be revalidated, and both serving paths answer If-Modified-Since with a 304.
	c.Header("Cache-Control", "no-cache")

	// VFS path: only when serial is empty (no device routing needed) and not a
	// RAW file needing OS-path conversion. RAW → JPEG requires dcraw/LibRaw which
	// only works with a real filesystem path, so those always fall through to
	// StorageService even when VFS is present.
	if serial == "" && (!wantsJPEG || !photoutil.IsRawFile(filePath)) {
		if fsys := fileutil.FilesVFS(deps.VFSRegistry()); fsys != nil {
			return downloadFileVFS(c, deps, fsys, access, filePath, wantsJPEG)
		}
	}

	// StorageService fallback (serial routing, RAW conversion, etc.)
	opened, err := fileutil.OpenDownload(fileutil.OpenDownloadParams{
		Storage:   deps.StorageService(),
		FilePath:  filePath,
		Serial:    serial,
		WantsJPEG: wantsJPEG,
	})
	if err != nil {
		return fileError(err)
	}
	if opened.File != nil {
		defer opened.File.Close()
	}

	switch opened.Kind {
	case fileutil.DownloadFolder:
		// Before the first byte of the archive: writing the zip commits the
		// headers, so a Content-Disposition set afterwards never reached the
		// client and the download landed with no .zip extension.
		c.Writer.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", opened.FileName))
		c.Writer.Header().Set("Content-Type", "application/octet-stream")
		if err := fileutil.ZipDir(c.Writer, opened.FullPath, strings.TrimSuffix(opened.FileName, ".zip")); err != nil {
			return serverutil.InternalServerError(err)
		}
		return nil // response written directly to writer

	case fileutil.DownloadRawJPEG, fileutil.DownloadJPEG:
		// Acquire IO semaphore: JPEG conversion is the most memory-intensive IO
		// path (full uncompressed image.Image decode + re-encode). Limit
		// concurrency to prevent RAM spikes and disk thrashing under concurrent
		// load — especially on spinning HDDs.
		if sem := deps.IOSemaphore(); sem != nil {
			if !sem.AcquireDefault(c.Request.Context()) {
				slog.Warn("download: IO semaphore timed out for JPEG conversion",
					"path", opened.FullPath,
					"available", sem.Available(),
					"cap", sem.Cap(),
				)
				c.Header("Retry-After", "5")
				c.JSON(http.StatusServiceUnavailable, gin.H{"error": "server busy, please retry"})
				return nil
			}
			defer sem.Release()
		}

		if opened.Kind == fileutil.DownloadRawJPEG {
			// The conversion is written straight onto the response, matching the
			// non-RAW branch below. Buffering it first put a whole converted
			// image on the heap per concurrent request (#1723). The trade is
			// that a mid-encode failure arrives after the headers, so it can
			// only be logged — same as the branch below.
			c.Header("Content-Disposition", fmt.Sprintf("inline; filename=%s", opened.FileName))
			c.Header("Content-Type", "image/jpeg")
			c.Status(http.StatusOK)
			if err := fileutil.WriteRawJPEG(c.Writer, opened.FullPath); err != nil {
				slog.Error("download: RAW to JPEG stream failed", "path", opened.FullPath, "err", err)
			}
			return nil
		}

		img, err := fileutil.DecodeImage(opened.File)
		if err != nil {
			return serverutil.InternalServerError(err)
		}

		c.Header("Content-Disposition", fmt.Sprintf("inline; filename=%s", opened.FileName))
		c.Header("Content-Type", "image/jpeg")
		c.Status(http.StatusOK)
		if err := fileutil.EncodeJPEG(c.Writer, img); err != nil {
			// Headers already committed; log only.
			slog.Error("download: JPEG stream encode failed", "path", opened.FullPath, "err", err)
		}
		return nil
	}

	opened.File.Close() // close before c.File re-opens it
	c.Header("Content-Disposition", fmt.Sprintf("inline; filename=%s", opened.FileName))
	c.Header("Content-Type", opened.ContentType)
	c.File(opened.FullPath)
	return nil // response written directly via c.File
}

var downloadFileRoute = serverutil.ApiRoute(
	"GET", "/files/download", downloadFile,
)
