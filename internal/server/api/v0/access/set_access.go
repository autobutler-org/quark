package v0_access

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// setAccess godoc
// @Summary Share a file or folder
// @Description Grants one active account or existing group read, write or owner on a path, replacing the level it had there, and returns the path's grants as they now stand. Only an owner of the path or an admin may share it. A non-admin can't change their own owner row on the path. Nobody, admins included, may share the users or groups folder itself on the internal device. Publishes access_changed for the path.
// @Tags access
// @Accept json
// @Produce json
// @Param body body setAccessBody true "The path, one account or group, and the level"
// @Success 200 {object} accessutil.GrantsResult
// @Failure 400 {object} serverutil.Response "a path in the trash, not exactly one account or group, a level other than read, write or owner, the caller's own owner row, or the users or groups folder itself"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller can read the path but doesn't own it"
// @Failure 404 {object} serverutil.Response "the caller can't read the path, or no active account or group has that id"
// @Failure 500 {object} serverutil.Response
// @Router /access [put]
func setAccess(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	var body setAccessBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(accessutil.ErrGrantTarget)
	}
	access, err := accessutil.LoadRequest(c, database, deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := accessutil.SetGrant(accessutil.SetGrantParams{
		Ctx:          c.Request.Context(),
		Database:     database,
		EventBus:     deps.EventBus(),
		Access:       access,
		DeviceSerial: body.DeviceSerial,
		Path:         body.RelPath,
		UserID:       body.UserID,
		GroupID:      body.GroupID,
		Level:        accessutil.ParseLevel(body.Level),
	})
	if err != nil {
		return grantError(err)
	}
	return serverutil.Ok().WithData(result)
}

var setAccessRoute = serverutil.ApiRoute("PUT", "/access", setAccess)
