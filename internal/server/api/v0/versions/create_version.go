package v0_versions

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// createVersion godoc
// @Summary Snapshot a file
// @Description Copy a file's current content into its version history. A named version needs a label of up to 100 characters; an auto version within 10 minutes of the file's last one is skipped. Content identical to the newest version is not copied again: the answer names that version with created false, and naming it labels it. Needs write access on the file.
// @Tags versions
// @Accept json
// @Produce json
// @Param body body createVersionRequest true "File and label"
// @Success 200 {object} SnapshotJSON
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 413 {object} serverutil.Response "Version history is full"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /versions [post]
func createVersion(c *gin.Context) *serverutil.Response {
	var req createVersionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	deps, fsys, refused := prepare(c, req.Path, accessutil.Write)
	if refused != nil {
		return refused
	}
	kind := fileversionutil.Kind(req.Kind)
	if kind == "" {
		kind = fileversionutil.KindNamed
	}
	res, err := deps.FileVersions().Snapshot(fileversionutil.SnapshotParams{
		Ctx:      c.Request.Context(),
		FS:       fsys,
		Path:     req.Path,
		Kind:     kind,
		Label:    req.Label,
		AuthorID: callerID(c),
	})
	if err != nil {
		return versionError(err)
	}
	return serverutil.Ok().WithData(SnapshotJSON{Version: res.Version, Created: res.Created})
}

var createVersionRoute = serverutil.ApiRoute(
	"POST", "/versions", createVersion,
)
