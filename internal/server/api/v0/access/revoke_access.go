package v0_access

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// revokeAccess godoc
// @Summary Stop sharing a file or folder
// @Description Removes one account's or group's grant on exactly this path and returns the path's grants as they now stand. Only an owner of the path or an admin may. Access a parent folder gives is removed on that folder instead. A non-admin can't remove their own owner row on the path; another owner or an admin may remove the last one. Publishes access_changed for the path.
// @Tags access
// @Accept json
// @Produce json
// @Param body body revokeAccessBody true "The path and one account or group"
// @Success 200 {object} accessutil.GrantsResult
// @Failure 400 {object} serverutil.Response "a path in the trash, not exactly one account or group, or the caller's own owner row"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller can read the path but doesn't own it"
// @Failure 404 {object} serverutil.Response "the caller can't read the path, or that account or group has no access to it"
// @Failure 409 {object} serverutil.Response "the access comes from a parent folder"
// @Failure 500 {object} serverutil.Response
// @Router /access [delete]
func revokeAccess(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	var body revokeAccessBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(accessutil.ErrGrantTarget)
	}
	access, err := accessutil.LoadRequest(c, database, deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := accessutil.RevokeGrant(accessutil.RevokeGrantParams{
		Ctx:          c.Request.Context(),
		Database:     database,
		EventBus:     deps.EventBus(),
		Access:       access,
		DeviceSerial: body.DeviceSerial,
		Path:         body.RelPath,
		UserID:       body.UserID,
		GroupID:      body.GroupID,
	})
	if err != nil {
		return grantError(err)
	}
	return serverutil.Ok().WithData(result)
}

var revokeAccessRoute = serverutil.ApiRoute("DELETE", "/access", revokeAccess)
