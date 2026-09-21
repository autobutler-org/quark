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
	"github.com/autobutler-org/quark/pkg/vfs"

	"github.com/gin-gonic/gin"
)

// convertXlsx godoc
// @Summary Convert a spreadsheet to a Quark spreadsheet
// @Description Reads an .xlsx or .xlsm workbook and writes it back as a sibling .qsheet, the format the Sheets editor opens. The workbook itself is left untouched. Answers 409 when a .qsheet of that name already exists and overwrite was not asked for. Needs read access on the workbook and write access on its directory; the caller owns a newly created .qsheet.
// @Tags files
// @Produce json
// @Param filePath query string true "Path to the .xlsx or .xlsm file to convert"
// @Param serial query string false "Device serial number"
// @Param overwrite query bool false "Replace an existing .qsheet of the same name"
// @Success 200 {object} ConvertXlsxJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 409 {object} serverutil.Response "Conflict"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/convert/xlsx [post]
func convertXlsx(c *gin.Context) *serverutil.Response {
	filePath := c.Query("filePath")
	if filePath == "" {
		return serverutil.BadRequest(errors.New("filePath query parameter is required"))
	}
	serial := c.Query("serial")

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

	result, err := fileutil.ConvertXlsxToQsheet(fileutil.ConvertXlsxParams{
		Ctx:       c.Request.Context(),
		Registry:  deps.VFSRegistry(),
		Storage:   deps.StorageService(),
		EventBus:  deps.EventBus(),
		FilePath:  filePath,
		Serial:    serial,
		Overwrite: c.Query("overwrite") == "true",
	})
	if err != nil {
		// A conversion runs for as long as the workbook is large, and the
		// access log only carries the status code, so a failure part-way
		// through is otherwise undiagnosable from the server logs (#1705).
		slog.Error("convert: xlsx conversion failed", "path", filePath, "err", err)
		if errors.Is(err, vfs.ErrConflict) {
			return serverutil.Conflict(err)
		}
		return fileError(err)
	}
	if !result.Replaced {
		grantOwner(c, deps, access, serial, result.Path)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(ConvertXlsxJSON{
		Path:  result.Path,
		Tabs:  result.Tabs,
		Rows:  result.Rows,
		Cells: result.Cells,
	})
}

var convertXlsxRoute = serverutil.ApiRoute(
	"POST", "/files/convert/xlsx", convertXlsx,
)
