package v0_files

import (
	"errors"
	"log/slog"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"

	"github.com/gin-gonic/gin"
)

// convertXlsx godoc
// @Summary Convert a spreadsheet to a Quark spreadsheet
// @Description Reads an .xlsx, .xlsm, .ods or .xls workbook, with the reader its extension names, and writes it back as a sibling .qsheet, the format the Sheets editor opens. The workbook itself is left untouched. Answers 409 when a .qsheet of that name already exists and overwrite was not asked for; with overwrite on the internal device, the replaced sheet is first snapshotted into its version history. Needs read access on the workbook and write access on its directory; the caller owns a newly created .qsheet.
// @Tags files
// @Produce json
// @Param filePath query string true "Path to the .xlsx, .xlsm, .ods or .xls file to convert"
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

	deps, access, resp := loadCaller(c)
	if resp != nil {
		return resp
	}
	if resp := gateReadWrite(access, serial, filePath, path.Dir(filePath)); resp != nil {
		return resp
	}

	result, err := fileutil.ConvertXlsxToQsheet(fileutil.ConvertXlsxParams{
		Ctx:       c.Request.Context(),
		Registry:  deps.VFSRegistry(),
		EventBus:  deps.EventBus(),
		FilePath:  filePath,
		Serial:    serial,
		Overwrite: c.Query("overwrite") == "true",
		// A conversion over a .qsheet snapshots it first (#2992).
		BeforeOverwrite: beforeSave(c, deps, serial),
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
		accessutil.RecordOwner(c.Request.Context(), deps.Database(), access, serial, result.Path)
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
