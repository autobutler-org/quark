package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listRecentFiles godoc
// @Summary List recently uploaded files
// @Description Returns files sorted by modification time (newest first) across all managed devices.
// @Tags files
// @Produce json
// @Param limit query int false "Maximum number of files to return (default 20, max 200)"
// @Param serial query []string false "Filter by device serial(s)"
// @Success 200 {array} FileNodeWithTimeJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/recent [get]
func listRecentFiles(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := fileutil.ListRecent(fileutil.ListRecentParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Storage:  deps.StorageService(),
		Serials:  c.QueryArray("serial"),
		Access:   access,
		Limit:    fileutil.ParseRecentLimit(c.Query("limit")),
	})
	if err != nil {
		return fileError(err)
	}
	return serverutil.Ok().WithData(result.Files)
}

var listRecentFilesRoute = serverutil.ApiRoute(
	"GET", "/files/recent", func(c *gin.Context) *serverutil.Response {
		return listRecentFiles(c)
	},
)
