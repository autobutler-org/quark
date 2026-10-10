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
// @Param filePaths query []string true "Array of file paths to delete, at most 1000 (fileutil.MaxDeleteFiles)"
// @Param serial query string false "Device serial number to filter by"
// @Success 202 {object} serverutil.Response "Accepted"
// @Failure 400 {object} serverutil.Response "Bad Request: no paths, more than 1000, or a path outside the files directory"
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
	params := fileutil.DeleteFilesParams{
		RootDir:   c.Query("rootDir"),
		FilePaths: filePaths,
		Serial:    c.Query("serial"),
	}
	// A batch that could never succeed is refused before any path is checked.
	if err := fileutil.ValidateDeleteFiles(params); err != nil {
		return fileError(err)
	}

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
		if refused := refuseHomeRoot(access, params.Serial, path.Join(params.RootDir, p)); refused != nil {
			return refused
		}
		check := access.Check(params.Serial, path.Join(params.RootDir, p), accessutil.Write)
		if !check.Readable {
			return serverutil.NotFound(errNoAccess)
		}
		if !check.Allowed {
			return serverutil.Forbidden(errReadOnly)
		}
	}

	params.Registry = deps.VFSRegistry()
	params.Storage = deps.StorageService()
	params.EventBus = deps.EventBus()
	params.Database = deps.Database()
	params.TrashedBy = access.Principal().UserID
	if _, err := fileutil.DeleteFiles(params); err != nil {
		return fileError(err)
	}
	return serverutil.Ok()
}

var deleteFilesRoute = serverutil.ApiRoute(
	"DELETE", "/files", deleteFiles,
)
