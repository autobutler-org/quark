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

// pptxContentType is the media type of a .pptx presentation.
const pptxContentType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"

// exportPptx godoc
// @Summary Download a Quark presentation as a PowerPoint file
// @Description Streams a .qslide back as a .pptx attachment, one slide per slide in show order. Shapes, lines and arrows, rich text, pictures, groups, rotation, stacking order, backgrounds and speaker notes carry across. Pictures are read from the files they name on the same device and embedded; one the caller cannot read, or that is missing, too large, or not a PNG, JPEG, GIF or BMP, is drawn as a gray placeholder with its alt text. Only reads: nothing is written beside the presentation. Needs read access on the .qslide.
// @Tags files
// @Produce application/vnd.openxmlformats-officedocument.presentationml.presentation
// @Param filePath query string true "Path to the .qslide file to export"
// @Param serial query string false "Device serial number"
// @Success 200 {file} file "The presentation"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/export/pptx [get]
func exportPptx(c *gin.Context) *serverutil.Response {
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

	// These go out with the first byte of the presentation, which is written
	// only once the file has opened and its first slide has been read.
	header := c.Writer.Header()
	header.Set("Content-Type", pptxContentType)
	header.Set("Content-Disposition",
		mime.FormatMediaType("attachment", map[string]string{"filename": fileutil.PptxExportName(filePath)}))
	_, err = fileutil.ExportQslideToPptx(fileutil.ExportPptxParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		FilePath: filePath,
		Serial:   serial,
		CanRead: func(imagePath string) bool {
			return access.Check(serial, imagePath, accessutil.Read).Readable
		},
		Out: c.Writer,
	})
	if err == nil {
		return nil
	}
	if c.Writer.Written() {
		// The status is committed and the package is cut short, which no
		// presentation app opens; all that is left is to log it.
		slog.Warn("export: pptx export stopped partway", "path", filePath, "err", err)
		return nil
	}
	// The error answer is JSON, and gin keeps a Content-Type already set.
	header.Del("Content-Type")
	header.Del("Content-Disposition")
	return fileError(err)
}

var exportPptxRoute = serverutil.ApiRoute(
	"GET", "/files/export/pptx", exportPptx,
)
