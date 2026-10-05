package v0_versions

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listVersions godoc
// @Summary List a file's versions
// @Description List the snapshots in a file's version history, newest first. A file with no history has none. Needs read access on the file.
// @Tags versions
// @Produce json
// @Param path query string true "Files-relative path of the file"
// @Success 200 {object} ListVersionsJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /versions [get]
func listVersions(c *gin.Context) *serverutil.Response {
	p := c.Query("path")
	deps, fsys, refused := prepare(c, p, accessutil.Read)
	if refused != nil {
		return refused
	}
	res, err := deps.FileVersions().List(fileversionutil.ListParams{
		Ctx:  c.Request.Context(),
		FS:   fsys,
		Path: p,
	})
	if err != nil {
		return versionError(err)
	}
	versions := res.Versions
	if versions == nil {
		versions = []VersionJSON{}
	}
	return serverutil.Ok().WithData(ListVersionsJSON{Versions: versions})
}

var listVersionsRoute = serverutil.ApiRoute(
	"GET", "/versions", listVersions,
)
