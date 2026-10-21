package v0_previews

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getPart godoc
// @Summary Get an image from inside a document
// @Description Streams one image a document preview's image block names, or a slides preview's "part:" picture reference with the prefix taken off. This is not a general zip browser: only a PNG, JPEG, GIF, WebP or BMP entry under the document's media folder (word/media/ for .docx and .docm, Pictures/ for .odt and .odp, ppt/media/ for .pptx, .pptm and .ppsx), named without any climbing, is served, and anything else is a 404. Needs read access on the document.
// @Tags previews
// @Produce png,jpeg,gif,image/webp,image/bmp
// @Param filePath query string true "Path to the document"
// @Param part query string true "The image's entry inside the document, e.g. word/media/image1.png, ppt/media/image3.png or Pictures/10000000000001.png"
// @Param serial query string false "Device serial number"
// @Success 200 {file} binary "Image content"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /previews/part [get]
func getPart(c *gin.Context) *serverutil.Response {
	part := c.Query("part")
	if part == "" {
		return serverutil.BadRequest(errors.New("part query parameter is required"))
	}
	deps, filePath, serial, refusal := readableDocument(c)
	if refusal != nil {
		return refusal
	}

	opened, err := fileutil.OpenDocumentPart(fileutil.OpenDocumentPartParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		FilePath: filePath,
		Serial:   serial,
		Part:     part,
	})
	if err != nil {
		return previewError(err)
	}
	defer func() {
		if err := opened.Close(); err != nil {
			slog.Warn("previews: closing a document part failed", "path", filePath, "part", part, "err", err)
		}
	}()

	c.Header("X-Content-Type-Options", "nosniff")
	c.DataFromReader(http.StatusOK, -1, opened.ContentType, opened.Reader, nil)
	return nil
}

var getPartRoute = serverutil.ApiRoute(
	"GET", "/previews/part", getPart,
)
