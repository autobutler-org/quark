package v0_files

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteFiles godoc
// @Summary Delete files
// @Description Move files to the device's trash (internal storage included), returning immediately. They can be restored through /trash/restore until the hourly purge deletes them after the retention period. DB cleanup and events are dispatched in the background.
// @Tags files
// @Produce json
// @Param rootDir query string false "Root directory"
// @Param filePaths query []string true "Array of file paths to delete"
// @Param serial query string false "Device serial number to filter by"
// @Success 202 {object} serverutil.Response "Accepted"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /files [delete]
func deleteFiles(c *gin.Context) *serverutil.Response {
	filePaths := c.QueryArray("filePaths")
	if len(filePaths) == 0 {
		return serverutil.BadRequest(errors.New("filePaths query parameter is required and must contain at least one file path"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	if _, err := fileutil.DeleteFiles(fileutil.DeleteFilesParams{
		Storage:   deps.StorageService(),
		EventBus:  deps.EventBus(),
		Database:  deps.Database(),
		RootDir:   c.Query("rootDir"),
		FilePaths: filePaths,
		Serial:    c.Query("serial"),
	}); err != nil {
		return fileError(err)
	}
	return serverutil.Ok()
}

var deleteFilesRoute = serverutil.ApiRoute(
	"DELETE", "/files", deleteFiles,
)
