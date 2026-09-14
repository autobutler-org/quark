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

// approveUser godoc
// @Summary Approve an account request
// @Description Turns a pending account request into an active account that can sign in. Admin-only.
// @Tags admin
// @Param username path string true "Username of the pending request"
// @Success 200
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no account request has that username"
// @Failure 500 {object} serverutil.Response
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

	if _, err := authutil.ApproveRequest(c.Request.Context(), database.Queries, authutil.ApproveRequestParams{
		Username: c.Param("username"),
	}); err != nil {
		return accountErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.Ok()
}

var approveUserRoute = serverutil.ApiRoute("PUT", "/admin/approve/:username", approveUser)
