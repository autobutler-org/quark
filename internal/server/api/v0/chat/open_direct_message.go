package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// openDirectMessage godoc
// @Summary Open a direct message
// @Description Opens the direct message (#2423) between the caller and the accounts named: the one these exact people already have, or a new one, which has no name, isn't listed to anyone outside it (admins included), and whose people never change. To add someone, open one with the bigger set. Each member holds the Member set. 1 to 15 other active accounts; repeats and the caller's own id are ignored. A new one publishes chat_channel_changed to its members. With fromChannelId, the caller is adding people to that direct message: they must be in it, and the set must keep everyone in it and add someone; a new one is then marked forked, so its members are told it started from an earlier conversation. Which one isn't stored.
// @Tags chat
// @Accept json
// @Produce json
// @Param body body openDirectMessageBody true "The other accounts"
// @Success 200 {object} chatutil.Channel "the direct message these people already had"
// @Success 201 {object} chatutil.Channel "a new direct message"
// @Failure 400 {object} serverutil.Response "no one else, too many people, or a fork that drops someone or adds no one"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "an account that doesn't exist or isn't active, or a fromChannelId the caller isn't in"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/dms [post]
func openDirectMessage(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	var body openDirectMessageBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrDirectMessageMembers)
	}
	result, err := chatutil.OpenDirectMessage(chatutil.OpenDirectMessageParams{
		Ctx:           c.Request.Context(),
		Database:      deps.Database(),
		EventBus:      deps.EventBus(),
		Principal:     principal,
		UserIDs:       body.UserIDs,
		FromChannelID: body.FromChannelID,
	})
	if err != nil {
		return chatError(err)
	}
	status := http.StatusOK
	if result.Created {
		status = http.StatusCreated
	}
	return serverutil.NewResponse().WithStatusCode(status).WithData(result.Channel)
}

var openDirectMessageRoute = serverutil.ApiRoute("POST", "/chat/dms", openDirectMessage)
