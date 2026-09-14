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

// demoteUser godoc
// @Summary Demote admin to regular user
// @Description Removes admin role from the given username. Refused with 409 while the Quark has at most one active admin. Admin-only.
// @Tags admin
// @Param username path string true "Username to demote"
// @Success 200 {object} serverutil.Response
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no account has that username"
// @Failure 409 {object} serverutil.Response "the last active admin"
// @Failure 500 {object} serverutil.Response
// @Router /admin/demote/{username} [put]
func demoteUser(c *gin.Context) *serverutil.Response {
	target := c.Param("username")
	if target == "" {
		return serverutil.BadRequest(errors.New("username is required"))
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}

	if err := authutil.DemoteFromAdmin(c.Request.Context(), database.Queries, target); err != nil {
		return accountErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.Ok()
}

var demoteUserRoute = serverutil.ApiRoute("PUT", "/admin/demote/:username", demoteUser)
