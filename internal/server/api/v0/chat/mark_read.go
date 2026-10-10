package v0_chat

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// markRead godoc
// @Summary Mark a chat channel read up to a message
// @Description Moves the caller's read marker in the channel to messageId, the newest message they have read there, and returns where the marker stands with the unread count past it: the messages after it that someone else wrote and nobody deleted. The marker never moves backward: an id at or before it changes nothing and still answers 200 with the marker as it stands. A move publishes chat_read_marker_changed with {channelId, lastReadMessageId, unreadCount} to the caller's own sessions alone, so their other devices clear the count. Needs read_messages; anyone else gets 404, delegated managers and admins included.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body markReadBody true "The newest message read"
// @Success 200 {object} chatutil.MarkReadResult
// @Failure 400 {object} serverutil.Response "the body isn't JSON with a messageId"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, the caller lacks read_messages, or the channel has no message with that id"
// @Failure 429 {object} serverutil.Response "the caller sent too many of these in a short time; the limit is per account"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/read [put]
func markRead(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	if limited := rateLimited(deps, principal, "read"); limited != nil {
		return limited
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxMarkReadRequestBytes)
	var body markReadBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(errors.New("a read marker needs a messageId"))
	}
	result, err := chatutil.MarkRead(chatutil.MarkReadParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal,
		ChannelID: id, MessageID: body.MessageID,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var markReadRoute = serverutil.ApiRoute("PUT", "/chat/channels/:id/read", markRead)
