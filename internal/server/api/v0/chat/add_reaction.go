package v0_chat

import (
	"net/http"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// addReaction godoc
// @Summary React to a chat message
// @Description Stores a reaction, base64 ciphertext the caller's client encrypted under the channel key of keyVersion, and sends the stored row to the channel's readers as chat_reaction_changed. The Quark never sees the emoji. Ciphertext is at most 256 bytes, and an account may hold at most 20 reactions on one message. Needs add_reactions; a reader without it gets 403, and anyone without read_messages 404, delegated managers and admins included.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Message id"
// @Param body body reactionBody true "The encrypted reaction"
// @Success 201 {object} chatutil.Reaction
// @Failure 400 {object} serverutil.Response "ciphertext too short or too long, or a key version the channel doesn't have"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller reads the channel but lacks add_reactions"
// @Failure 404 {object} serverutil.Response "no such message, or the caller lacks read_messages in its channel"
// @Failure 409 {object} serverutil.Response "the message was deleted, or the caller already holds 20 reactions on it"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id}/reactions [post]
func addReaction(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		return serverutil.NotFound(chatutil.ErrMessageNotFound)
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxReactionRequestBytes)
	var body reactionBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidReaction)
	}
	result, err := chatutil.AddReaction(chatutil.AddReactionParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal,
		MessageID: id, KeyVersion: body.KeyVersion, Ciphertext: body.Ciphertext,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(result.Reaction)
}

var addReactionRoute = serverutil.ApiRoute("POST", "/chat/messages/:id/reactions", addReaction)
