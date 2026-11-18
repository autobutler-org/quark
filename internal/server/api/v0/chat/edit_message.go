package v0_chat

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// editMessage godoc
// @Summary Edit a chat message
// @Description Replaces the message's ciphertext with new base64 ciphertext the author's client encrypted under the channel key of keyVersion, sets editedAt, and sends the edited row, without its reactions, to the channel's readers as chat_message_edited. No earlier version is kept. Only the author may edit, and only while they hold read_messages; send_messages is not needed. Another reader gets 403, and anyone without read_messages 404, delegated managers, demoted authors and admins included. The ciphertext follows a post's rules: at most 16 KiB, and a nonce the channel already holds under keyVersion on another message is 409. A deleted message or a poll is 409.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Message id"
// @Param body body editMessageBody true "The new encrypted message"
// @Success 200 {object} chatutil.Message
// @Failure 400 {object} serverutil.Response "ciphertext too short, or a key version the channel doesn't have"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller reads the channel but didn't write the message"
// @Failure 404 {object} serverutil.Response "no such message, or the caller lacks read_messages in its channel"
// @Failure 409 {object} serverutil.Response "the message was deleted, is a poll, or another message holds this nonce"
// @Failure 413 {object} serverutil.Response "ciphertext over 16 KiB"
// @Failure 429 {object} serverutil.Response "the caller sent too many of these in a short time; the limit is per account"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id} [put]
func editMessage(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	if limited := rateLimited(deps, principal, "messages"); limited != nil {
		return limited
	}
	id, failed := messageID(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxMessageRequestBytes)
	var body editMessageBody
	if err := c.ShouldBindJSON(&body); err != nil {
		if tooLarge := new(http.MaxBytesError); errors.As(err, &tooLarge) {
			return chatError(chatutil.ErrMessageTooLarge)
		}
		return serverutil.BadRequest(chatutil.ErrInvalidMessage)
	}
	result, err := chatutil.EditMessage(chatutil.EditMessageParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal,
		MessageID: id, KeyVersion: body.KeyVersion, Ciphertext: body.Ciphertext,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Message)
}

var editMessageRoute = serverutil.ApiRoute("PUT", "/chat/messages/:id", editMessage)
