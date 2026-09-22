package v0_files

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// downloadArchiveFile godoc
// @Summary Download a single file from inside an archive
// @Description Reads the specified entry from the archive and streams it to the client. No data is extracted to disk. With format=jpeg an image entry other than camera RAW is converted and served as image/jpeg; every other entry is served as it is.
// @Tags files
// @Produce octet-stream,jpeg
// @Param filePath query string true "Path to the archive file (relative to device files directory)"
// @Param entryPath query string true "Path of the entry inside the archive"
// @Param serial query string false "Device serial number"
// @Param format query string false "Output format conversion ('jpeg' converts HEIC, TIFF, BMP and other decodable images to JPEG)"
// @Param downloadToken query string false "Token from POST /files/download-token, for a browser link that cannot send an Authorization header. It is good for one download: the first request, then retries that resume it with a Range header or start it over without one, until the file is delivered or 10 minutes pass with no request. The response is then always an attachment."
// @Success 200 {file} binary "File content"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Entry not found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "Server busy converting other images"
// @Security BearerAuth
// @Router /files/download-archive-file [get]
func downloadArchiveFile(c *gin.Context) *serverutil.Response {
	archivePath := c.Query("filePath")
	entryPath := c.Query("entryPath")
	serial := c.Query("serial")

	if archivePath == "" || entryPath == "" {
		return serverutil.BadRequest(errors.New("filePath and entryPath query parameters are required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(serial, archivePath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	entry, err := fileutil.OpenArchiveEntry(fileutil.OpenArchiveEntryParams{
		Ctx:         c.Request.Context(),
		Registry:    deps.VFSRegistry(),
		Storage:     deps.StorageService(),
		ArchivePath: archivePath,
		EntryPath:   entryPath,
		Serial:      serial,
		WantsJPEG:   c.Query("format") == "jpeg",
	})
	if err != nil {
		return fileError(err)
	}
	defer entry.Reader.Close()

	if entry.Kind == fileutil.DownloadJPEG {
		// A conversion decodes the whole image, so it shares the IO semaphore
		// with the regular download conversions.
		if sem := deps.IOSemaphore(); sem != nil {
			if !sem.AcquireDefault(c.Request.Context()) {
				slog.Warn("download-archive-file: IO semaphore timed out for JPEG conversion",
					"archive", archivePath,
					"entry", entryPath,
					"available", sem.Available(),
					"cap", sem.Cap(),
				)
				c.Header("Retry-After", "5")
				c.JSON(http.StatusServiceUnavailable, gin.H{"error": "server busy, please retry"})
				return nil
			}
			defer sem.Release()
		}

		img, err := fileutil.DecodeImage(entry.Reader)
		if err != nil {
			return serverutil.InternalServerError(err)
		}

		c.Header("Content-Disposition", contentDisposition(c, entry.FileName, "inline; filename=\""+entry.FileName+"\""))
		c.Header("Content-Type", entry.ContentType)
		c.Status(http.StatusOK)
		if err := fileutil.EncodeJPEG(c.Writer, img); err != nil {
			// Headers already committed; log only.
			slog.Error("download-archive-file: JPEG stream encode failed", "archive", archivePath, "entry", entryPath, "err", err)
		}
		return nil
	}

	c.Header("Content-Disposition", contentDisposition(c, entry.FileName, "attachment; filename=\""+entry.FileName+"\""))
	if entry.Size >= 0 {
		c.Header("Content-Length", strconv.FormatInt(entry.Size, 10))
	}
	c.DataFromReader(http.StatusOK, entry.Size, entry.ContentType, entry.Reader, nil)
	return nil
}

var downloadArchiveFileRoute = serverutil.ApiRoute(
	"GET", "/files/download-archive-file", func(c *gin.Context) *serverutil.Response {
		return downloadArchiveFile(c)
	},
)
