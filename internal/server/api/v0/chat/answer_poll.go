package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// answerPoll godoc
// @Summary Answer a chat poll
// @Description Stores the caller's answer to a poll, base64 ciphertext of the answer padded to 4 KiB and encrypted under the channel key of keyVersion, so it is exactly 4136 bytes. When the poll allows changing an answer a second one replaces the first; otherwise it is 409. On a poll that names who answered, the stored row goes as chat_poll_answer_changed to the readers who may see it: everyone, or while a results-after-close poll is open only its author and the caller. An anonymous poll sends chat_poll_answers_changed with no answer instead, and while a results-after-close anonymous poll is open that note reaches the author on a delay. The returned answer of an anonymous poll has no timestamps and an id that does not follow arrival order. The Quark never sees the answer. Needs read_messages and add_reactions; a reader without add_reactions gets 403, and anyone without read_messages 404.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Poll message id"
// @Param body body pollAnswerBody true "The encrypted answer"
// @Success 200 {object} chatutil.PollAnswer
// @Failure 400 {object} serverutil.Response "ciphertext not exactly 4136 bytes, or a key version the channel doesn't have"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller reads the channel but lacks add_reactions"
// @Failure 404 {object} serverutil.Response "no such message, the message isn't a poll, or the caller lacks read_messages in its channel"
// @Failure 409 {object} serverutil.Response "the poll is closed, or the caller already answered and the poll doesn't allow changing an answer"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id}/answer [put]
func answerPoll(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := messageID(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxPollAnswerRequestBytes)
	var body pollAnswerBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidPollAnswer)
	}
	result, err := chatutil.AnswerPoll(chatutil.AnswerPollParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(), Principal: principal,
		MessageID: id, KeyVersion: body.KeyVersion, Ciphertext: body.Ciphertext,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Answer)
}

var answerPollRoute = serverutil.ApiRoute("PUT", "/chat/messages/:id/answer", answerPoll)
