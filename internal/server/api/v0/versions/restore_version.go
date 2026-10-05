package v0_versions

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// restoreVersion godoc
// @Summary Restore a version
// @Description Put a version's content back in the file. The file's current content is snapshotted first, labeled "Before restore", so restoring that snapshot undoes this. The file is replaced atomically, and an upload event announces it. Needs write access on the file.
// @Tags versions
// @Produce json
// @Param id path string true "Version id"
// @Param path query string true "Files-relative path of the file"
// @Success 200 {object} RestoreJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /versions/{id}/restore [post]
func restoreVersion(c *gin.Context) *serverutil.Response {
	p := c.Query("path")
	deps, fsys, refused := prepare(c, p, accessutil.Write)
	if refused != nil {
		return refused
	}
	res, err := deps.FileVersions().Restore(fileversionutil.RestoreParams{
		Ctx:      c.Request.Context(),
		FS:       fsys,
		EventBus: deps.EventBus(),
		Path:     p,
		ID:       c.Param("id"),
		AuthorID: callerID(c),
	})
	if err != nil {
		return versionError(err)
	}
	return serverutil.Ok().WithData(RestoreJSON{Restored: res.Restored, Backup: res.Backup})
}

var restoreVersionRoute = serverutil.ApiRoute(
	"POST", "/versions/:id/restore", restoreVersion,
)
