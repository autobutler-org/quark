package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// importPptx godoc
// @Summary Import a PowerPoint file as a Quark presentation
// @Description Reads a .pptx (or .pptm or .ppsx) and writes it as a .qslide, the format the Slides editor opens, in rootDir — the PowerPoint file's own folder when rootDir is left out. Its pictures are copied into a <name>_media folder beside the presentation. Nothing is overwritten: a name already taken is kept, and the import lands under the next free numbered name, as Talk_(1).qslide. What the editor cannot show — charts, tables, SmartArt, video, animations — is skipped and listed in the warnings, slide by slide. The PowerPoint file itself is left untouched. Needs read access on it and write access on rootDir; the caller owns what the import created.
// @Tags files
// @Produce json
// @Param filePath query string true "Path to the .pptx file to import"
// @Param rootDir query string false "Folder to write the presentation into; defaults to the .pptx's folder"
// @Param serial query string false "Device serial number"
// @Success 200 {object} ImportPptxJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/import/pptx [post]
func importPptx(c *gin.Context) *serverutil.Response {
	return importPresentation(c, "pptx", fileutil.ImportPptxToQslide)
}

var importPptxRoute = serverutil.ApiRoute(
	"POST", "/files/import/pptx", importPptx,
)
