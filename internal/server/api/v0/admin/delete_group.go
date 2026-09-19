package v0_admin

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteGroup godoc
// @Summary Delete a group
// @Description Deletes a group, its memberships and every share made to it, so its members lose what only the group gave them. The everyone group can't be deleted. Publishes access_changed with no path. Admin-only.
// @Tags admin
// @Param id path int true "Group id"
// @Success 204
// @Failure 400 {object} serverutil.Response "the everyone group"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no group has that id"
// @Failure 500 {object} serverutil.Response
// @Router /admin/groups/{id} [delete]
func deleteGroup(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	groupID, err := idParam(c, "id", grouputil.ErrGroupNotFound)
	if err != nil {
		return groupErrorResponse(err)
	}

	if _, err := grouputil.DeleteGroup(c.Request.Context(), grouputil.DeleteGroupParams{
		Database: database,
		GroupID:  groupID,
	}); err != nil {
		return groupErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var deleteGroupRoute = serverutil.ApiRoute("DELETE", "/admin/groups/:id", deleteGroup)
