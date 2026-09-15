package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listArchive godoc
// @Summary List contents of an archive file at a given virtual path
// @Description Opens the archive at filePath and returns the direct children of subPath as FileNodeJSON entries. No data is extracted to disk — only archive headers are read.
// @Tags files
// @Produce json
// @Param filePath query string true "Path to the archive file (relative to device files directory)"
// @Param subPath query string false "Virtual subdirectory inside the archive to list (empty = root)"
// @Param serial query string false "Device serial number"
// @Success 200 {array} FileNodeJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /files/list-archive [get]
func listArchive(c *gin.Context) *serverutil.Response {
	filePath := c.Query("filePath")
	if filePath == "" {
		return serverutil.BadRequest(nil)
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !access.Check(c.Query("serial"), filePath, accessutil.Read).Readable {
		return serverutil.NotFound(errNoAccess)
	}

	result, err := fileutil.ListArchive(fileutil.ListArchiveParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Storage:  deps.StorageService(),
		FilePath: filePath,
		SubPath:  c.Query("subPath"),
		Serial:   c.Query("serial"),
	})
	if err != nil {
		return fileError(err)
	}
	return serverutil.Ok().WithData(result.Entries)
}

var listArchiveRoute = serverutil.ApiRoute(
	"GET", "/files/list-archive", func(c *gin.Context) *serverutil.Response {
		return listArchive(c)
	},
)
