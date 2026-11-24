package v0_chat

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// markBranchRead godoc
// @Summary Mark a chat message's side conversation read up to a reply
// @Description Moves the caller's read marker in the side conversation of the message to messageId, the newest reply they have read there, and returns where the marker stands with rootId and the branch's unread count past it: the live replies after it that someone else wrote. As on PUT /chat/channels/{id}/read, the marker never moves backward, and a move publishes chat_read_marker_changed, with rootId and the branch's unreadCount, to the caller's own sessions alone. Needs read_messages on the message's channel; anyone else gets 404, delegated managers and admins included.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Root message id"
// @Param body body markReadBody true "The newest reply read"
// @Success 200 {object} chatutil.MarkReadResult
// @Failure 400 {object} serverutil.Response "the body isn't JSON with a messageId"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such message, the caller lacks read_messages on its channel, or messageId is no reply to it"
// @Failure 429 {object} serverutil.Response "the caller sent too many of these in a short time; the limit is per account"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id}/read [put]
func markBranchRead(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	if limited := rateLimited(deps, principal, "read"); limited != nil {
		return limited
	}
	id, failed := messageID(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxMarkReadRequestBytes)
	var body markReadBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(errors.New("a read marker needs a messageId"))
	}
	result, err := chatutil.MarkBranchRead(chatutil.MarkBranchReadParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal,
		RootID: id, MessageID: body.MessageID,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var markBranchReadRoute = serverutil.ApiRoute("PUT", "/chat/messages/:id/read", markBranchRead)
