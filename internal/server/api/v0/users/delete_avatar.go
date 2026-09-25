package v0_users

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/avatarutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// deleteAvatar godoc
// @Summary Remove your profile picture
// @Description Removes the caller's profile picture; clients fall back to initials. Removing a picture that is not there succeeds. Publishes account_changed when one was removed.
// @Tags users
// @Success 204 "No Content"
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /users/me/avatar [delete]
func deleteAvatar(c *gin.Context) *serverutil.Response {
	userID, err := callerID(c)
	if err != nil {
		return serverutil.Unauthorized(err)
	}
	result, err := avatarutil.Remove(avatarutil.RemoveParams{
		DataDir: storageutil.GetDataDir(),
		UserID:  userID,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if result.Removed {
		publishAccountChanged(c)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var deleteAvatarRoute = serverutil.ApiRoute("DELETE", "/users/me/avatar", deleteAvatar)
