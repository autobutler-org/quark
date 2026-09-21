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

// deleteUser godoc
// @Summary Delete an account
// @Description Deletes an account, its sessions, its shares and its group memberships. Its files stay where they are, and every path it owned becomes owned by the admin deleting it. An admin cannot delete their own account here, and the only active admin cannot be deleted. Admin-only.
// @Tags admin
// @Produce json
// @Param username path string true "Username to delete"
// @Success 200 {object} deleteUserResponse
// @Failure 400 {object} serverutil.Response "the caller's own account"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no account has that username"
// @Failure 409 {object} serverutil.Response "the only active admin"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/users/{username} [delete]
func deleteUser(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	actorID, ok := ctxutil.Get[int64](c, "userID")
	if !ok || actorID == 0 {
		return serverutil.Unauthorized(errors.New("authentication required"))
	}

	result, err := authutil.DeleteUser(c.Request.Context(), authutil.DeleteUserParams{
		Database:    database,
		ActorUserID: actorID,
		Username:    c.Param("username"),
	})
	if err != nil {
		return accountErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.Ok().WithData(deleteUserResponse{OwnerRowsReassigned: result.OwnerRowsReassigned})
}

var deleteUserRoute = serverutil.ApiRoute("DELETE", "/admin/users/:username", deleteUser)
