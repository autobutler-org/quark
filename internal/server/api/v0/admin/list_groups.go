package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listGroups godoc
// @Summary List groups
// @Description Returns every group with its members, the built-in everyone group first and the rest by name. everyone lists no members: it includes every active account. Admin-only.
// @Tags admin
// @Produce json
// @Success 200 {array} grouputil.Group
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /admin/groups [get]
func listGroups(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}

	result, err := grouputil.ListGroups(c.Request.Context(), grouputil.ListGroupsParams{Database: database})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result.Groups)
}

var listGroupsRoute = serverutil.ApiRoute("GET", "/admin/groups", listGroups)
