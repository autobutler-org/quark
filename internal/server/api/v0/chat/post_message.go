package v0_chat

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// postMessage godoc
// @Summary Post an encrypted message to a chat channel
// @Description Stores ciphertext, base64, that the caller's client encrypted under the channel key of keyVersion, and sends the stored row to the channel's readers as chat_message_created. The Quark never sees the text. A ciphertext's 24-byte nonce is taken once per channel and key version: repeating your own live post byte for byte returns it with 200 and stores nothing, and any other reuse is 409. clientMessageId, up to 64 bytes, names the send: a retry encrypts again under a fresh nonce, so it carries the same clientMessageId, and one the caller already sent to this channel returns that message with 200 and stores nothing, whatever the ciphertext. attachmentIds, when set, names up to 10 attachments the caller already uploaded to this channel and has not bound to a message. Each id is 64 lowercase hex characters, sent in the clear so the Quark can delete the files with the message; the name, the media type and the key stay in the ciphertext. They are bound to this message in the same transaction. A retry of this clientMessageId or ciphertext still returns the stored message when those ids are already bound to it. More than 10, or an id that is not 64 lowercase hex characters, is 400. An id the caller cannot bind is 404 and the message is not stored. Ciphertext is at most 16 KiB. poll, when set, makes the message a poll whose question and options are in the ciphertext: closesAt, when set, is when it stops taking answers and has to be in the future and at most a year after the post; allowChange lets an account replace its answer; anonymous serves answers without who gave them, to everyone; resultsAfterClose shows answers only to the author until it closes. A poll field of the wrong type, or one the Quark does not know, is refused. Needs send_messages, and attach_files when attachmentIds is set; a reader without the one it needs gets 403, and anyone without read_messages 404, delegated managers and admins included.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body postMessageBody true "The encrypted message"
// @Success 201 {object} chatutil.Message
// @Success 200 {object} chatutil.Message "the caller already posted this clientMessageId or exactly this ciphertext; nothing new was stored"
// @Failure 400 {object} serverutil.Response "ciphertext too short, a key version the channel doesn't have, a clientMessageId over 64 bytes, more than 10 attachment ids, an attachment id that is not 64 lowercase hex characters, poll settings of the wrong shape, or a closesAt in the past or more than a year ahead"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller reads the channel but lacks send_messages, or names attachments without attach_files"
// @Failure 404 {object} serverutil.Response "no such channel, the caller lacks read_messages, or an attachment the caller cannot bind to this message"
// @Failure 409 {object} serverutil.Response "the channel already has a message with this nonce under keyVersion, deleted ones included"
// @Failure 413 {object} serverutil.Response "ciphertext over 16 KiB"
// @Failure 429 {object} serverutil.Response "the caller sent too many of these in a short time; the limit is per account"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/messages [post]
func postMessage(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	if limited := rateLimited(deps, principal, "messages"); limited != nil {
		return limited
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxMessageRequestBytes)
	var body postMessageBody
	if err := bindPostMessage(c.Request.Body, &body); err != nil {
		if tooLarge := new(http.MaxBytesError); errors.As(err, &tooLarge) {
			return chatError(chatutil.ErrMessageTooLarge)
		}
		// A poll field that does not decode is its own error. Any other bind
		// failure stays the ciphertext one, which is what a bad message is (#3944).
		if errors.Is(err, chatutil.ErrMalformedPoll) {
			return chatError(err)
		}
		return serverutil.BadRequest(chatutil.ErrInvalidMessage)
	}
	result, err := chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal,
		ChannelID: id, KeyVersion: body.KeyVersion, Ciphertext: body.Ciphertext, ClientMessageID: body.ClientMessageID,
		Poll: body.Poll, AttachmentIDs: body.AttachmentIDs,
	})
	if err != nil {
		return chatError(err)
	}
	status := http.StatusCreated
	if result.Repeated {
		status = http.StatusOK
	}
	return serverutil.NewResponse().WithStatusCode(status).WithData(result.Message)
}

var postMessageRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/messages", postMessage)
