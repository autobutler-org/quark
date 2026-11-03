package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listPollAnswers godoc
// @Summary List the answers to a chat poll the caller may see
// @Description Returns the answers the caller may see, as ciphertext: oldest first, or by ciphertext when the poll is anonymous. An anonymous poll's answers carry no userId, createdAt or updatedAt, for the author too, and an id that does not follow arrival order; the caller's own is marked mine. While a results-after-close poll is open, anyone but its author gets only their own answer. Needs read_messages; anyone else gets 404.
// @Tags chat
// @Produce json
// @Param id path int true "Poll message id"
// @Success 200 {object} chatutil.ListPollAnswersResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such message, the message isn't a poll, or the caller lacks read_messages in its channel"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id}/answers [get]
func listPollAnswers(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := messageID(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.ListPollAnswers(chatutil.ListPollAnswersParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal, MessageID: id,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listPollAnswersRoute = serverutil.ApiRoute("GET", "/chat/messages/:id/answers", listPollAnswers)
