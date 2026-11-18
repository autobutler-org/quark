package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// postTyping godoc
// @Summary Say the caller is typing in a chat channel
// @Description Sends chat_typing with {channelId, userId} to the channel's other readers, the holders of read_messages, and to no one else. It is ephemeral: nothing is stored or logged, there is no body, and it carries nothing of what is typed. A client sends it every few seconds while its user types and readers let it lapse on their own. Needs send_messages; a reader without it gets 403, and anyone without read_messages 404, delegated managers and admins included.
// @Tags chat
// @Param id path int true "Channel id"
// @Success 204
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller reads the channel but lacks send_messages"
// @Failure 404 {object} serverutil.Response "no such channel, or the caller lacks read_messages"
// @Failure 429 {object} serverutil.Response "the caller sent too many of these in a short time; the limit is per account"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/typing [post]
func postTyping(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	if limited := rateLimited(deps, principal, "typing"); limited != nil {
		return limited
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	if _, err := chatutil.Typing(chatutil.TypingParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal, ChannelID: id,
	}); err != nil {
		return chatError(err)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var postTypingRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/typing", postTyping)
