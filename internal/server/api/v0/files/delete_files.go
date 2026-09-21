package v0_files

import (
	"errors"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
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
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files [delete]
func deleteFiles(c *gin.Context) *serverutil.Response {
	filePaths := c.QueryArray("filePaths")
	if len(filePaths) == 0 {
		return serverutil.BadRequest(errors.New("filePaths query parameter is required and must contain at least one file path"))
	}
	rootDir := c.Query("rootDir")
	serial := c.Query("serial")

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	// Every path is checked before any is trashed, so a batch the caller may
	// only partly change changes nothing.
	for _, p := range filePaths {
		if refused := refuseHomeRoot(access, serial, path.Join(rootDir, p)); refused != nil {
			return refused
		}
		check := access.Check(serial, path.Join(rootDir, p), accessutil.Write)
		if !check.Readable {
			return serverutil.NotFound(errNoAccess)
		}
		if !check.Allowed {
			return serverutil.Forbidden(errReadOnly)
		}
	}

	if _, err := fileutil.DeleteFiles(fileutil.DeleteFilesParams{
		Storage:   deps.StorageService(),
		EventBus:  deps.EventBus(),
		Database:  deps.Database(),
		RootDir:   rootDir,
		FilePaths: filePaths,
		Serial:    serial,
		TrashedBy: access.Principal().UserID,
	}); err != nil {
		return fileError(err)
	}
	return serverutil.Ok()
}

var deleteFilesRoute = serverutil.ApiRoute(
	"DELETE", "/files", deleteFiles,
)
