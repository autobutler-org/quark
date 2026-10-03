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
// @Description Stores ciphertext, base64, that the caller's client encrypted under the channel key of keyVersion, and sends the stored row to the channel's readers as chat_message_created. The Quark never sees the text. A ciphertext's 24-byte nonce is taken once per channel and key version: repeating your own live post byte for byte returns it with 200 and stores nothing, and any other reuse is 409. Ciphertext is at most 16 KiB. Needs send_messages; a reader without it gets 403, and anyone without read_messages 404, delegated managers and admins included.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body postMessageBody true "The encrypted message"
// @Success 201 {object} chatutil.Message
// @Success 200 {object} chatutil.Message "the caller already posted exactly this ciphertext; nothing new was stored"
// @Failure 400 {object} serverutil.Response "ciphertext too short, or a key version the channel doesn't have"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller reads the channel but lacks send_messages"
// @Failure 404 {object} serverutil.Response "no such channel, or the caller lacks read_messages"
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
	if err := c.ShouldBindJSON(&body); err != nil {
		if tooLarge := new(http.MaxBytesError); errors.As(err, &tooLarge) {
			return chatError(chatutil.ErrMessageTooLarge)
		}
		return serverutil.BadRequest(chatutil.ErrInvalidMessage)
	}
	result, err := chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal,
		ChannelID: id, KeyVersion: body.KeyVersion, Ciphertext: body.Ciphertext,
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
