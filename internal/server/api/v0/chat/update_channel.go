package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// updateChannel godoc
// @Summary Rename a chat channel or change its topic
// @Description Changes a channel's name, topic or both; a field left out is unchanged. Only an owner of the channel or an admin may. The name rules are create's. level in the answer is empty for an admin who isn't a member. Publishes chat_channel_changed.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body updateChannelBody true "The new name, topic or both"
// @Success 200 {object} chatutil.Channel
// @Failure 400 {object} serverutil.Response "an invalid name or topic"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller is a member but not an owner"
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member or an admin"
// @Failure 409 {object} serverutil.Response "another channel has that name"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id} [patch]
func updateChannel(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	var body updateChannelBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidName)
	}
	result, err := chatutil.UpdateChannel(chatutil.UpdateChannelParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		ChannelID: id,
		Name:      body.Name,
		Topic:     body.Topic,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Channel)
}

var updateChannelRoute = serverutil.ApiRoute("PATCH", "/chat/channels/:id", updateChannel)
