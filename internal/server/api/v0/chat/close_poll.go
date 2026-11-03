package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// closePoll godoc
// @Summary Close a chat poll
// @Description Stops the poll taking answers and tells the channel's readers with chat_poll_closed. Closing a closed poll returns it unchanged and announces nothing. Only the poll's author may close it, and only while they hold read_messages; anyone else who reads the channel gets 403, and anyone without read_messages 404.
// @Tags chat
// @Produce json
// @Param id path int true "Poll message id"
// @Success 200 {object} chatutil.Poll
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller isn't the poll's author"
// @Failure 404 {object} serverutil.Response "no such message, the message isn't a poll, or the caller lacks read_messages in its channel"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id}/close [post]
func closePoll(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := messageID(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.ClosePoll(chatutil.ClosePollParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal, MessageID: id,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Poll)
}

var closePollRoute = serverutil.ApiRoute("POST", "/chat/messages/:id/close", closePoll)
