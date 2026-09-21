package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// disableUser godoc
// @Summary Turn an account off
// @Description Stops an account from signing in, and ends its sessions and open event streams. The account keeps its files and shares, so turning it back on restores it. An admin cannot turn off their own account, and the only active admin cannot be turned off. Admin-only.
// @Tags admin
// @Param username path string true "Username to turn off"
// @Success 200
// @Failure 400 {object} serverutil.Response "the caller's own account"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no active account has that username"
// @Failure 409 {object} serverutil.Response "the only active admin"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/disable/{username} [put]
func disableUser(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	actorID, ok := ctxutil.Get[int64](c, "userID")
	if !ok {
		return serverutil.Unauthorized(errors.New("authentication required"))
	}

	if _, err := authutil.DisableUser(c.Request.Context(), authutil.DisableUserParams{
		Database:    database,
		ActorUserID: actorID,
		Username:    c.Param("username"),
	}); err != nil {
		return accountErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.Ok()
}

var disableUserRoute = serverutil.ApiRoute("PUT", "/admin/disable/:username", disableUser)
