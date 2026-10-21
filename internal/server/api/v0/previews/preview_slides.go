package v0_previews

import (
	"context"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// previewSlides godoc
// @Summary Preview a presentation
// @Description Streams a .pptx, .pptm, .ppsx or .odp presentation as JSON for the read-only presentation viewer: {deck, warnings}, the deck a .qslide presentation and each warning a {slide, message}. The deck is written slide by slide as it is read, and each picture is named in place by its entry in the package after a "part:" prefix (part:ppt/media/image3.png, part:Pictures/10000000000001.png), which GET /previews/part serves; nothing is stored. The warnings, what was left out or approximated with slide 0 for the deck, come after the deck because they are known only at its end, so a body that does not parse was cut off by a server error. Macros are never read. A file that is not what its name says, is encrypted, or is past the import limits is a 400. Needs read access on the presentation.
// @Tags previews
// @Produce json
// @Param filePath query string true "Path to the presentation"
// @Param serial query string false "Device serial number"
// @Success 200 {object} fileutil.SlidesPreview
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
	_, err := fileutil.PreviewSlides(fileutil.PreviewSlidesParams{
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
		// The status is committed; the unclosed object tells the client.
		slog.Warn("previews: slides stream stopped partway", "path", filePath, "err", err)
		return nil
	}
	slog.Error("previews: slides preview failed", "path", filePath, "err", err)
	return previewError(err)
}

var previewSlidesRoute = serverutil.ApiRoute(
	"GET", "/previews/slides", previewSlides,
)
