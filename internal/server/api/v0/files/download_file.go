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
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
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
// @Param downloadToken query string false "Token from POST /files/download-token, for a browser link that cannot send an Authorization header. It is good for one download: the first request, then retries that resume it with a Range header or start it over without one, until the file is delivered or 10 minutes pass with no request. The response is then always an attachment."
// @Success 200 {file} file
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 422 {object} serverutil.Response "Image too large to convert"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "Every folder zip slot is busy, or no JPEG conversion slot came free; retry after the Retry-After header"
// @Header 503 {integer} Retry-After "seconds to wait before retrying"
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

	// One path for every device: the namespace of the device the request
	// names (#2642). A RAW file asked for as JPEG is the one case that needs a
	// host path, which the namespace hands over for the conversion tool.
	fsys, err := fileutil.FilesVFS(deps.VFSRegistry(), serial)
	if err != nil {
		return fileError(err)
	}
	ctx := c.Request.Context()
	opened, err := fileutil.OpenVFSDownload(fileutil.OpenVFSDownloadParams{
		Ctx:       ctx,
		FS:        fsys,
		FilePath:  filePath,
		WantsJPEG: wantsJPEG,
	})
	if err != nil {
		return fileError(err)
	}

	switch opened.Kind {
	case fileutil.DownloadFolder:
		release, ok := acquireZipSlot(c, deps, filePath)
		if !ok {
			return nil
		}
		defer release()
		// Before the first byte of the archive: writing the zip commits the
		// headers, so a Content-Disposition set afterwards never reached the
		// client and the download landed with no .zip extension.
		c.Writer.Header().Set("Content-Disposition", contentDisposition(c, opened.FileName, fmt.Sprintf("attachment; filename=%q", opened.FileName)))
		c.Writer.Header().Set("Content-Type", "application/octet-stream")
		if err := fileutil.ZipVFSDir(ctx, fsys, filePath, strings.TrimSuffix(opened.FileName, ".zip"), access, c.Writer); err != nil {
			return zipError(c, filePath, err)
		}
		return nil

	case fileutil.DownloadRawJPEG, fileutil.DownloadJPEG:
		// Acquire IO semaphore: JPEG conversion is the most memory-intensive IO
		// path (full uncompressed image.Image decode + re-encode). Limit
		// concurrency to prevent RAM spikes and disk thrashing under concurrent
		// load — especially on spinning HDDs.
		class := iosemutil.Decode
		if opened.Kind == fileutil.DownloadRawJPEG {
			class = iosemutil.Raw
		}
		if sem := deps.IOSemaphore().For(class); sem != nil {
			if !sem.AcquireDefault(ctx) {
				slog.Warn("download: IO semaphore timed out for JPEG conversion",
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

		if opened.Kind == fileutil.DownloadRawJPEG {
			// The conversion is written straight onto the response, matching the
			// non-RAW branch below. Buffering it first put a whole converted
			// image on the heap per concurrent request (#1723). The trade is
			// that a mid-encode failure arrives after the headers, so it can
			// only be logged — same as the branch below.
			c.Header("Content-Disposition", contentDisposition(c, opened.FileName, fmt.Sprintf("inline; filename=%s", opened.FileName)))
			c.Header("Content-Type", opened.ContentType)
			c.Status(http.StatusOK)
			if err := fileutil.WriteRawJPEG(c.Writer, opened.HostPath); err != nil {
				slog.Error("download: RAW to JPEG stream failed", "path", filePath, "err", err)
			}
			return nil
		}

		r, err := fsys.Open(ctx, filePath)
		if err != nil {
			return serverutil.NotFound(err)
		}
		defer r.Close()

		img, err := fileutil.DecodeImage(r)
		if err != nil {
			return decodeError(err)
		}

		c.Header("Content-Disposition", contentDisposition(c, opened.FileName, fmt.Sprintf("inline; filename=%s", opened.FileName)))
		c.Header("Content-Type", opened.ContentType)
		c.Status(http.StatusOK)
		if err := fileutil.EncodeJPEG(c.Writer, img); err != nil {
			// Headers already committed; log only.
			slog.Error("download: JPEG stream encode failed", "path", filePath, "err", err)
		}
		return nil
	}

	r, err := fsys.Open(ctx, filePath)
	if err != nil {
		return serverutil.NotFound(err)
	}
	defer r.Close()

	c.Header("Content-Disposition", contentDisposition(c, opened.FileName, fmt.Sprintf("inline; filename=%s", opened.FileName)))
	c.Header("Content-Type", opened.ContentType)

	// A vfs.File seeks, so http.ServeContent honors HTTP range requests
	// (RFC 7233) — required for video seeking and resumable downloads.
	http.ServeContent(c.Writer, c.Request, opened.Info.Name, opened.Info.ModTime, r)
	return nil
}

var downloadFileRoute = serverutil.ApiRoute(
	"GET", "/files/download", downloadFile,
)
