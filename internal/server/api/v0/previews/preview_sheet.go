package v0_previews

import (
	"context"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// previewSheet godoc
// @Summary Preview a spreadsheet
// @Description Streams an .xlsx, .xlsm, .ods or .xls workbook as .qsheet JSON for the read-only sheet viewer: {tabs}, each tab a {name, data: {rows}} with every cell the value it displays. The reader is chosen by extension, the same one POST /files/convert/xlsx runs, and nothing is stored. Rows are written as they are read, so a body that does not parse was cut off by a server error. Formulas contribute their cached value and macros are never read. A file that is not what its name says, is encrypted, or is past the conversion limits is a 400. Needs read access on the workbook.
// @Tags previews
// @Produce json
// @Param filePath query string true "Path to the workbook"
// @Param serial query string false "Device serial number"
// @Success 200 {object} fileutil.SheetPreview
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "Server busy converting other documents"
// @Security BearerAuth
// @Router /previews/sheet [get]
func previewSheet(c *gin.Context) *serverutil.Response {
	deps, filePath, serial, refusal := readableDocument(c)
	if refusal != nil {
		return refusal
	}
	release, busy := acquireDecode(c, deps)
	if busy != nil {
		return busy
	}
	defer release()

	ctx, cancel := context.WithTimeout(c.Request.Context(), previewDeadline)
	defer cancel()
	_, err := fileutil.PreviewSheet(fileutil.PreviewSheetParams{
		Ctx:      ctx,
		Registry: deps.VFSRegistry(),
		FilePath: filePath,
		Serial:   serial,
		Out:      streamWriter{c: c, contentType: "application/json; charset=utf-8"},
	})
	if err == nil {
		return nil
	}
	if c.Writer.Written() {
		// The status is committed; the unclosed envelope tells the client.
		slog.Warn("previews: sheet stream stopped partway", "path", filePath, "err", err)
		return nil
	}
	slog.Error("previews: sheet preview failed", "path", filePath, "err", err)
	return previewError(err)
}

var previewSheetRoute = serverutil.ApiRoute(
	"GET", "/previews/sheet", previewSheet,
)
