package v0_files

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listFiles godoc
// @Summary Lists files
// @Schemes http https
// @Description merges files across all managed devices for the given filePath. If deviceSerial is empty, list files across all devices. Otherwise, only for the specified device
// @Tags files
// @Produce json
// @Success 200 {array} FileNodeJSON
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Param rootDir query string false "File dir to list"
// @Param serial query string false "Device serial number to filter by"
// @Router /files [get]
func listFiles(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := loadAccess(c, deps)
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := fileutil.ListFiles(fileutil.ListFilesParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Storage:  deps.StorageService(),
		Access:   access,
		RootDir:  c.Query("rootDir"),
		Serials:  c.QueryArray("serial"),
	})
	if err != nil {
		return fileError(err)
	}
	return serverutil.Ok().WithData(result.Files)
}

var listFilesRoute = serverutil.ApiRoute(
	"GET", "/files", func(c *gin.Context) *serverutil.Response {
		return listFiles(c)
	},
)
