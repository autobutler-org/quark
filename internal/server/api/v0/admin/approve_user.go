package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// approveUser godoc
// @Summary Approve an account request
// @Description Turns a pending account request into an active account that can sign in, with a home under users/ on the internal device that it owns. An existing folder of that name under users/ becomes the home. Admin-only.
// @Tags admin
// @Param username path string true "Username of the pending request"
// @Success 200
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no account request has that username"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/approve/{username} [put]
func approveUser(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := authutil.ApproveRequest(c.Request.Context(), authutil.ApproveRequestParams{
		Database: database,
		Username: c.Param("username"),
		FilesDir: filesDir,
	})
	if err != nil {
		return accountErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
		bus.Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: result.FolderPath})
	}
	return serverutil.Ok()
}

var approveUserRoute = serverutil.ApiRoute("PUT", "/admin/approve/:username", approveUser)
