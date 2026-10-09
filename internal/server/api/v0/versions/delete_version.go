package v0_versions

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteVersion godoc
// @Summary Delete a named version
// @Description Delete a named version from a file's history. Auto versions are removed by retention only. Needs write access on the file.
// @Tags versions
// @Produce json
// @Param id path string true "Version id"
// @Param path query string true "Files-relative path of the file"
// @Success 200 {object} serverutil.Response "Ok"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /versions/{id} [delete]
func deleteVersion(c *gin.Context) *serverutil.Response {
	p := c.Query("path")
	deps, fsys, refused := prepare(c, p, accessutil.Write)
	if refused != nil {
		return refused
	}
	if _, err := deps.FileVersions().Delete(fileversionutil.DeleteParams{
		Ctx:  c.Request.Context(),
		FS:   fsys,
		Path: p,
		ID:   c.Param("id"),
	}); err != nil {
		return versionError(err)
	}
	return serverutil.Ok()
}

var deleteVersionRoute = serverutil.ApiRoute(
	"DELETE", "/versions/:id", deleteVersion,
)
