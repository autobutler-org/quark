package v0_previews

import (
	"context"
	"log/slog"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// previewSlides godoc
// @Summary Preview a presentation
// @Description Streams a .pptx, .pptm or .ppsx presentation as .qslide JSON, a slide at a time, for the read-only presentation viewer: what "Open as Quark slides" would write, but stored nowhere. A picture is named by its entry in the package, as part:ppt/media/image3.png, which GET /previews/part serves. Macros are never opened. The import's warnings are counted in the X-Quark-Import-Warnings trailer, sent after the body because they are known only once the last slide is read; a stream without it was cut off by a server error. A file that is not what its name says is a 400. Needs read access on the presentation.
// @Tags previews
// @Produce json
// @Param filePath query string true "Path to the presentation"
// @Param serial query string false "Device serial number"
// @Success 200 {string} string ".qslide JSON"
// @Header 200 {integer} X-Quark-Import-Warnings "How many things the import left out or approximated, sent as a trailer"
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
	// A trailer is declared before the body and filled in after it.
	c.Header("Trailer", importWarningsTrailer)
	result, err := fileutil.PreviewSlides(fileutil.PreviewSlidesParams{
		Ctx:      ctx,
		Registry: deps.VFSRegistry(),
		FilePath: filePath,
		Serial:   serial,
		Out:      streamWriter{c: c, contentType: "application/json"},
	})
	if err == nil {
		c.Writer.Header().Set(importWarningsTrailer, strconv.Itoa(len(result.Warnings)))
		return nil
	}
	if c.Writer.Written() {
		// The status is committed; the missing trailer tells the client.
		slog.Warn("previews: slides stream stopped partway", "path", filePath, "err", err)
		return nil
	}
	slog.Error("previews: slides preview failed", "path", filePath, "err", err)
	return previewError(err)
}

var previewSlidesRoute = serverutil.ApiRoute(
	"GET", "/previews/slides", previewSlides,
)
