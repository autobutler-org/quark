package v0_files

import (
	"errors"
	"log/slog"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
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
	filePath := c.Query("filePath")
	if filePath == "" {
		return serverutil.BadRequest(errors.New("filePath query parameter is required"))
	}
	rootDir, ok := c.GetQuery("rootDir")
	if !ok {
		rootDir = path.Dir(filePath)
	}
	if rootDir == "." {
		rootDir = ""
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
	if !access.Check(serial, rootDir, accessutil.Write).Allowed {
		return serverutil.Forbidden(errReadOnly)
	}

	result, err := fileutil.ImportPptxToQslide(fileutil.ImportPptxParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		EventBus: deps.EventBus(),
		FilePath: filePath,
		RootDir:  rootDir,
		Serial:   serial,
	})
	if err != nil {
		// An import runs for as long as the package is large, and the access
		// log only carries the status code (#1705).
		slog.Error("import: pptx import failed", "path", filePath, "err", err)
		return fileError(err)
	}
	grantOwner(c, deps, access, serial, result.Path)
	if result.MediaDirCreated {
		grantOwner(c, deps, access, serial, result.MediaDir)
	} else {
		for _, p := range result.Media {
			grantOwner(c, deps, access, serial, p)
		}
	}

	warnings := make([]ImportWarningJSON, 0, len(result.Warnings))
	for _, w := range result.Warnings {
		warnings = append(warnings, ImportWarningJSON{Slide: w.Slide, Message: w.Message})
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(ImportPptxJSON{
		Path:     result.Path,
		MediaDir: result.MediaDir,
		Slides:   result.Slides,
		Pictures: result.Pictures,
		Warnings: warnings,
	})
}

var importPptxRoute = serverutil.ApiRoute(
	"POST", "/files/import/pptx", importPptx,
)
