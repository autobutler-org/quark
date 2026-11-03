package v0_previews

import (
	"bytes"
	"context"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// previewSlides godoc
// @Summary Preview a presentation
// @Description Converts a .pptx, .pptm or .ppsx presentation to .qslide JSON for the read-only presentation viewer: what "Open as Quark slides" would write, but stored nowhere. A picture is named by its entry in the package, as part:ppt/media/image3.png, which GET /previews/part serves. Macros are never opened. The import's warnings are counted in the X-Quark-Import-Warnings header, so the viewer can say that some things were not shown. A file that is not what its name says is a 400. Needs read access on the presentation.
// @Tags previews
// @Produce json
// @Param filePath query string true "Path to the presentation"
// @Param serial query string false "Device serial number"
// @Success 200 {string} string ".qslide JSON"
// @Header 200 {integer} X-Quark-Import-Warnings "How many things the import left out or approximated"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "Server busy converting other documents"
// @Security BearerAuth
// @Router /previews/slides [get]
func previewSlides(c *gin.Context) *serverutil.Response {
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
	// The .qslide is held until the import returns, because the warning
	// count is a header and is known only after the last slide. It is the
	// text and layout of the deck, bounded by pptxutil's import limits; the
	// package and its pictures still stream and are never held.
	var qslide bytes.Buffer
	result, err := fileutil.PreviewSlides(fileutil.PreviewSlidesParams{
		Ctx:      ctx,
		Registry: deps.VFSRegistry(),
		FilePath: filePath,
		Serial:   serial,
		Out:      &qslide,
	})
	if err != nil {
		slog.Error("previews: slides preview failed", "path", filePath, "err", err)
		return previewError(err)
	}
	c.Header(importWarningsHeader, strconv.Itoa(len(result.Warnings)))
	c.Header("X-Content-Type-Options", "nosniff")
	c.Data(http.StatusOK, "application/json", qslide.Bytes())
	return nil
}

var previewSlidesRoute = serverutil.ApiRoute(
	"GET", "/previews/slides", previewSlides,
)
