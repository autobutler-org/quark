package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// importOdp godoc
// @Summary Import an OpenDocument presentation as a Quark presentation
// @Description Reads an .odp and writes it as a .qslide, the format the Slides editor opens, in rootDir — the .odp's own folder when rootDir is left out. Its pictures are copied into a <name>_media folder beside the presentation. Nothing is overwritten: a name already taken is kept, and the import lands under the next free numbered name, as Talk_(1).qslide. What the editor cannot show — charts, embedded objects, video, animations, freeform paths — is skipped or approximated and listed in the warnings, slide by slide. Macros are never read. A file that is not an .odp, is not what its name says, is encrypted, or is past the import limits is a 400. The .odp itself is left untouched. Needs read access on it and write access on rootDir; the caller owns what the import created.
// @Tags files
// @Produce json
// @Param filePath query string true "Path to the .odp file to import"
// @Param rootDir query string false "Folder to write the presentation into; defaults to the .odp's folder"
// @Param serial query string false "Device serial number"
// @Success 200 {object} ImportPptxJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/import/odp [post]
func importOdp(c *gin.Context) *serverutil.Response {
	return importPresentation(c, "odp", func(params fileutil.ImportPptxParams) (fileutil.ImportPptxResult, error) {
		result, err := fileutil.ImportOdpToQslide(fileutil.ImportOdpParams(params))
		return fileutil.ImportPptxResult(result), err
	})
}

var importOdpRoute = serverutil.ApiRoute(
	"POST", "/files/import/odp", importOdp,
)
