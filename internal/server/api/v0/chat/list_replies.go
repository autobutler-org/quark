package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listReplies godoc
// @Summary Page the encrypted replies in a chat message's side conversation
// @Description Returns the replies posted with this message as their rootId, oldest first, each with its reactions. before, after and limit work as they do on GET /chat/channels/{id}/messages. Deleted replies come back as tombstones. A message no one replied to, a deleted one among them, has an empty page. Needs read_messages on the message's channel; anyone else gets 404, delegated managers and admins included.
// @Tags chat
// @Produce json
// @Param id path int true "Root message id"
// @Param before query int false "Page backward from this message id"
// @Param after query int false "Page forward from this message id"
// @Param limit query int false "At most this many, 50 by default, capped at 200"
// @Success 200 {object} chatutil.ListMessagesResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such message, or the caller lacks read_messages on its channel"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/messages/{id}/replies [get]
func listReplies(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := messageID(c)
	if failed != nil {
		return failed
	}
	after, forward := c.GetQuery("after")
	afterID, _ := strconv.ParseInt(after, 10, 64)
	before, _ := strconv.ParseInt(c.Query("before"), 10, 64)
	limit, _ := strconv.ParseInt(c.Query("limit"), 10, 64)
	result, err := chatutil.ListReplies(chatutil.ListRepliesParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal, MessageID: id,
		Before: before, After: afterID, Forward: forward, Limit: limit,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listRepliesRoute = serverutil.ApiRoute("GET", "/chat/messages/:id/replies", listReplies)
