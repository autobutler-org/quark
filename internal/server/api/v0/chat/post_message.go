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
// @Description Stores ciphertext, base64, that the caller's client encrypted under the channel key of keyVersion, and sends the stored row to the channel's members as chat_message_created. The Quark never sees the text. Ciphertext is at most 16 KiB. Needs write; a read member gets 403 and anyone else 404, admins included.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body postMessageBody true "The encrypted message"
// @Success 201 {object} chatutil.Message
// @Failure 400 {object} serverutil.Response "ciphertext too short, or a key version the channel doesn't have"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller can only read the channel"
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member"
// @Failure 413 {object} serverutil.Response "ciphertext over 16 KiB"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/messages [post]
func postMessage(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
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
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(result.Message)
}

var postMessageRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/messages", postMessage)
