package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// createChannel godoc
// @Summary Create a chat channel
// @Description Creates a private channel and makes the caller its owner. Any signed-in account may. The name is trimmed, has 1 to 64 characters and no line breaks or tabs, and is unique ignoring case; the topic has at most 512 characters. Publishes chat_channel_changed.
// @Tags chat
// @Accept json
// @Produce json
// @Param body body createChannelBody true "The name and an optional topic"
// @Success 201 {object} chatutil.Channel
// @Failure 400 {object} serverutil.Response "an invalid name or topic"
// @Failure 401 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "another channel has that name"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels [post]
func createChannel(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	var body createChannelBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidName)
	}
	result, err := chatutil.CreateChannel(chatutil.CreateChannelParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		Name:      body.Name,
		Topic:     body.Topic,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(result.Channel)
}

var createChannelRoute = serverutil.ApiRoute("POST", "/chat/channels", createChannel)
