package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteChannel godoc
// @Summary Delete a chat channel
// @Description Deletes a channel and its members. Only an owner of the channel or an admin may, and general can't be deleted. Publishes chat_channel_changed to everyone who was a member.
// @Tags chat
// @Param id path int true "Channel id"
// @Success 204
// @Failure 400 {object} serverutil.Response "the channel is general"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller is a member but not an owner"
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member or an admin"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id} [delete]
func deleteChannel(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	if _, err := chatutil.DeleteChannel(chatutil.DeleteChannelParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		ChannelID: id,
	}); err != nil {
		return chatError(err)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var deleteChannelRoute = serverutil.ApiRoute("DELETE", "/chat/channels/:id", deleteChannel)
