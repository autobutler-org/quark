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

// enableUser godoc
// @Summary Turn an account back on
// @Description Lets a disabled account sign in again, with everything it owned when it was turned off. Admin-only.
// @Tags admin
// @Param username path string true "Username to turn back on"
// @Success 200
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no disabled account has that username"
// @Failure 500 {object} serverutil.Response
// @Router /admin/enable/{username} [put]
func enableUser(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}

	if _, err := authutil.EnableUser(c.Request.Context(), database.Queries, authutil.EnableUserParams{
		Username: c.Param("username"),
	}); err != nil {
		return accountErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.Ok()
}

var enableUserRoute = serverutil.ApiRoute("PUT", "/admin/enable/:username", enableUser)
