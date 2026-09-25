package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listMessages godoc
// @Summary Page a chat channel's encrypted messages
// @Description Returns messages oldest first. With after, the page starts after that id (after=0 is the beginning), which is how a client catches up on anything the events socket dropped. Otherwise it ends before before, or at the newest message when before is left out. Deleted messages come back as tombstones with deletedAt and no ciphertext. Members only; anyone else gets 404, admins included.
// @Tags chat
// @Produce json
// @Param id path int true "Channel id"
// @Param before query int false "Page backward from this message id"
// @Param after query int false "Page forward from this message id"
// @Param limit query int false "At most this many, 50 by default, capped at 200"
// @Success 200 {object} chatutil.ListMessagesResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/messages [get]
func listMessages(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	after, forward := c.GetQuery("after")
	afterID, _ := strconv.ParseInt(after, 10, 64)
	before, _ := strconv.ParseInt(c.Query("before"), 10, 64)
	limit, _ := strconv.ParseInt(c.Query("limit"), 10, 64)
	result, err := chatutil.ListMessages(chatutil.ListMessagesParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal, ChannelID: id,
		Before: before, After: afterID, Forward: forward, Limit: limit,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listMessagesRoute = serverutil.ApiRoute("GET", "/chat/channels/:id/messages", listMessages)
