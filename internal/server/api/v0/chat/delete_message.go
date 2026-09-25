package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteMessage godoc
// @Summary Delete a chat message
// @Description Wipes the message's ciphertext and sets deletedAt, leaving a tombstone so paging stays contiguous, and tells the channel's members with chat_message_deleted. Allowed for the message's author or an owner of its channel; another member gets 403 and anyone outside the channel 404, admins included.
// @Tags chat
// @Produce json
// @Param id path int true "Message id"
// @Success 200 {object} chatutil.Message
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller neither wrote it nor owns the channel"
// @Failure 404 {object} serverutil.Response "no such message, or the caller isn't in its channel"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id} [delete]
func deleteMessage(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return serverutil.NotFound(chatutil.ErrMessageNotFound)
	}
	result, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal, MessageID: id,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Message)
}

var deleteMessageRoute = serverutil.ApiRoute("DELETE", "/chat/messages/:id", deleteMessage)
