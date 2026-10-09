package v0_files

import (
	"errors"
	"log/slog"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// extractFile godoc
// @Summary Extract an archive in place
// @Description Extracts a zip, tar, tar.gz, tgz, rar or 7z archive into a new folder beside it named after the archive without its extension, numbered when that name is taken; a bare .gz decompresses to a new file beside it. Nothing appears under the new name until the extraction is complete. Needs read access on the archive and write access on its directory; the caller owns what is extracted.
// @Tags files
// @Produce json
// @Param filePath query string true "Path to the archive to extract"
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

	extracted, err := fileutil.ExtractArchive(fileutil.ExtractArchiveParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		EventBus: deps.EventBus(),
		FilePath: filePath,
		Serial:   serial,
	})
	if err != nil {
		// The access log only ever showed the status code, so an extraction
		// failure was undiagnosable from the server logs (#1705).
		slog.Error("extract: archive extraction failed", "path", filePath, "serial", serial, "err", err)
		return fileError(err)
	}

	grantOwner(c, deps, access, serial, extracted.CreatedPath)
	return serverutil.Ok()
}

var extractFileRoute = serverutil.ApiRoute(
	"POST", "/files/extract", extractFile,
)
