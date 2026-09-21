package v0_files

import (
	"errors"
	"log/slog"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// extractFile godoc
// @Summary Extract a zip archive in place
// @Description Extracts a zip file into a subdirectory named after the archive (without its extension) in the same directory. Needs read access on the archive and write access on its directory; the caller owns what is extracted.
// @Tags files
// @Produce json
// @Param filePath query string true "Path to the zip file to extract"
// @Param serial query string false "Device serial number"
// @Success 200 {object} serverutil.Response "OK"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/extract [post]
func extractFile(c *gin.Context) *serverutil.Response {
	filePath := c.Query("filePath")
	serial := c.Query("serial")

	if filePath == "" {
		return serverutil.BadRequest(errors.New("filePath query parameter is required"))
	}

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
	if !access.Check(serial, path.Dir(filePath), accessutil.Write).Allowed {
		return serverutil.Forbidden(errReadOnly)
	}

	// VFS path: only for .zip archives when no serial is provided.
	// Non-zip types (rar/tar/7z/gz) require mholt/archiver OS-path handling,
	// so those always fall through to StorageService.
	if serial == "" && strings.ToLower(filepath.Ext(filePath)) == ".zip" {
		if fsys := fileutil.FilesVFS(deps.VFSRegistry()); fsys != nil {
			extracted, err := fileutil.ExtractZipVFS(c.Request.Context(), fsys, filePath)
			if err != nil {
				// The access log only ever showed the status code, so an
				// extraction failure was undiagnosable from the server logs (#1705).
				slog.Error("extract: VFS zip extraction failed", "path", filePath, "err", err)
				return fileError(err)
			}
			if extracted.Created {
				grantOwner(c, deps, access, serial, extracted.DestDir)
			}
			return serverutil.Ok()
		}
	}

	extracted, err := deps.StorageService().ExtractFile(storageutil.ExtractFileParams{
		FilePath:     filePath,
		DeviceSerial: serial,
	})
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "file not found") {
			return serverutil.NotFound(err)
		}
		if strings.Contains(msg, "file is not an archive") || strings.Contains(msg, "only zip archives are supported") {
			return serverutil.BadRequest(err)
		}
		// A compression method Go's archive/zip cannot decompress (Deflate64 and
		// friends) is the caller's archive, not a server fault. The VFS branch
		// above answers 400 for it, and this one serves the same file whenever a
		// serial is passed, so it cannot answer something else (#1705).
		if strings.Contains(msg, "unsupported compression") {
			return serverutil.BadRequest(err)
		}
		return serverutil.InternalServerError(err)
	}

	grantOwner(c, deps, access, serial, extracted.CreatedPath)
	return serverutil.Ok()
}

var extractFileRoute = serverutil.ApiRoute(
	"POST", "/files/extract", extractFile,
)
