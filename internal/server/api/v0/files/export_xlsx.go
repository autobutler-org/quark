package v0_files

import (
	"errors"
	"log/slog"
	"mime"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// xlsxContentType is the media type of an .xlsx workbook.
const xlsxContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

// exportXlsx godoc
// @Summary Download a Quark spreadsheet as an Excel workbook
// @Description Streams a .qsheet back as an .xlsx attachment, one worksheet per tab in tab order. Values, bold, italic, colors, alignment, number formats, column widths and frozen panes carry across; formulas are written as their text, since the editor's formula dialect is not Excel's and the server has no evaluator to supply the cached results Excel expects. Only reads: nothing is written beside the sheet. Needs read access on the .qsheet.
// @Tags files
// @Produce application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
// @Param filePath query string true "Path to the .qsheet file to export"
// @Param serial query string false "Device serial number"
// @Success 200 {file} file "The workbook"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/export/xlsx [get]
func exportXlsx(c *gin.Context) *serverutil.Response {
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

	// These go out with the first byte of the workbook, which is written only
	// once the sheet has opened and its first tab has been read.
	header := c.Writer.Header()
	header.Set("Content-Type", xlsxContentType)
	header.Set("Content-Disposition",
		mime.FormatMediaType("attachment", map[string]string{"filename": fileutil.XlsxExportName(filePath)}))
	_, err = fileutil.ExportQsheetToXlsx(fileutil.ExportXlsxParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		FilePath: filePath,
		Serial:   serial,
		Out:      c.Writer,
	})
	if err == nil {
		return nil
	}
	if c.Writer.Written() {
		// The status is committed and the workbook is cut short, which no
		// spreadsheet app opens; all that is left is to log it.
		slog.Warn("export: xlsx export stopped partway", "path", filePath, "err", err)
		return nil
	}
	// The error answer is JSON, and gin keeps a Content-Type already set.
	header.Del("Content-Type")
	header.Del("Content-Disposition")
	return fileError(err)
}

var exportXlsxRoute = serverutil.ApiRoute(
	"GET", "/files/export/xlsx", exportXlsx,
)
