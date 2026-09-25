package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getChannelKeys godoc
// @Summary Get a chat channel's key versions and the caller's grants
// @Description Returns the channel's key versions, the newest (0 before any exists, when the first member to open the channel creates version 1), the caller's own key grants, and whether the key needs rotating because someone outside the channel holds the current version. Members only: anyone else, admins included, gets 404.
// @Tags chat
// @Produce json
// @Param id path int true "Channel id"
// @Success 200 {object} chatutil.GetChannelKeysResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys [get]
func getChannelKeys(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.GetChannelKeys(chatutil.GetChannelKeysParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal, ChannelID: id,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var getChannelKeysRoute = serverutil.ApiRoute("GET", "/chat/channels/:id/keys", getChannelKeys)
