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

// removeGroupMember godoc
// @Summary Take an account out of a group
// @Description Takes an account out of a group, whatever the account's status, so it loses what only the group gave it. Members of the everyone group can't be changed. Publishes access_changed with no path. Admin-only.
// @Tags admin
// @Param id path int true "Group id"
// @Param userId path int true "Account id"
// @Success 204
// @Failure 400 {object} serverutil.Response "the everyone group"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no group has that id, or that account isn't in the group"
// @Failure 500 {object} serverutil.Response
// @Router /admin/groups/{id}/members/{userId} [delete]
func removeGroupMember(c *gin.Context) *serverutil.Response {
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
	userID, err := idParam(c, "userId", grouputil.ErrNotMember)
	if err != nil {
		return groupErrorResponse(err)
	}

	if _, err := grouputil.RemoveMember(c.Request.Context(), grouputil.RemoveMemberParams{
		Database: database,
		GroupID:  groupID,
		UserID:   userID,
	}); err != nil {
		return groupErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var removeGroupMemberRoute = serverutil.ApiRoute("DELETE", "/admin/groups/:id/members/:userId", removeGroupMember)
