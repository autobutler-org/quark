package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// listFilesByType godoc
// @Summary List all files of a given type
// @Description Recursively walks all managed devices and returns files whose fileType matches the given value, sorted newest-first.
// @Tags files
// @Produce json
// @Param fileType query string true "File type to filter by (e.g. qdoc, qsheet)"
// @Param serial query []string false "Filter by device serial(s)"
// @Success 200 {array} FileNodeWithTimeJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/by-type [get]
func listFilesByType(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	fileTypeParam := c.Query("fileType")
	if fileTypeParam == "" {
		return serverutil.BadRequest(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := fileutil.ListByType(fileutil.ListByTypeParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Storage:  deps.StorageService(),
		Serials:  c.QueryArray("serial"),
		Access:   access,
		FileType: storageutil.FileType(fileTypeParam),
	})
	if err != nil {
		return fileError(err)
	}
	return serverutil.Ok().WithData(result.Files)
}

var listFilesByTypeRoute = serverutil.ApiRoute(
	"GET", "/files/by-type", func(c *gin.Context) *serverutil.Response {
		return listFilesByType(c)
	},
)
