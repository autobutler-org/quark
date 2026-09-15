package v0_admin

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// addGroupMember godoc
// @Summary Add an account to a group
// @Description Puts an active account in a group, so it reaches what the group was shared. Adding a member again changes nothing. Members of the everyone group can't be changed. Publishes access_changed with no path when the membership is new. Admin-only.
// @Tags admin
// @Param id path int true "Group id"
// @Param userId path int true "Account id"
// @Success 204
// @Failure 400 {object} serverutil.Response "the everyone group"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no group has that id, or no active account has that id"
// @Failure 500 {object} serverutil.Response
// @Router /admin/groups/{id}/members/{userId} [put]
func addGroupMember(c *gin.Context) *serverutil.Response {
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
	userID, err := idParam(c, "userId", authutil.ErrUserNotFound)
	if err != nil {
		return groupErrorResponse(err)
	}

	result, err := grouputil.AddMember(c.Request.Context(), grouputil.AddMemberParams{
		Database: database,
		GroupID:  groupID,
		UserID:   userID,
	})
	if err != nil {
		return groupErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil && result.Added {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccessChanged})
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var addGroupMemberRoute = serverutil.ApiRoute("PUT", "/admin/groups/:id/members/:userId", addGroupMember)
