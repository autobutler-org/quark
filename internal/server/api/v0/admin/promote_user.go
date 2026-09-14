package v0_admin

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// promoteUser godoc
// @Summary Promote user to admin
// @Description Grants admin role to the given username. Admin-only.
// @Tags admin
// @Param username path string true "Username to promote"
// @Success 200 {object} serverutil.Response
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /admin/promote/{username} [put]
func promoteUser(c *gin.Context) *serverutil.Response {
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

	if err := authutil.PromoteToAdmin(c.Request.Context(), database.Queries, target); err != nil {
		return serverutil.InternalServerError(fmt.Errorf("promote user: %w", err))
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.Ok()
}

var promoteUserRoute = serverutil.ApiRoute("PUT", "/admin/promote/:username", promoteUser)
