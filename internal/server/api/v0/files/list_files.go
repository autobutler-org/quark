package v0_files

import (
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
// @Failure 400 {object} serverutil.Response "Bad Request: a rootDir outside the files directory"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Param rootDir query string false "File dir to list"
// @Param serial query string false "Device serial number to filter by"
// @Security BearerAuth
// @Router /files [get]
func listFiles(c *gin.Context) *serverutil.Response {
	deps, access, resp := loadCaller(c)
	if resp != nil {
		return resp
	}

	result, err := fileutil.ListFiles(fileutil.ListFilesParams{
		Ctx:      c.Request.Context(),
		Registry: deps.VFSRegistry(),
		Access:   access,
		RootDir:  c.Query("rootDir"),
		Serials:  c.QueryArray("serial"),
		Index:    deps.FileIndex(),
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
