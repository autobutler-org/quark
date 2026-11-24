package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listBranches godoc
// @Summary Page a chat channel's side conversations
// @Description Returns the channel's messages that have at least one reply that is not deleted, each with its branch summary as GET /chat/channels/{id}/messages gives it, newest last reply first. A deleted message with live replies comes back as a tombstone. Reactions and poll answers are left out. nextBefore, present on a full page, is the before of the next. Needs read_messages; anyone else gets 404, delegated managers and admins included.
// @Tags chat
// @Produce json
// @Param id path int true "Channel id"
// @Param before query int false "Page from the branches whose newest reply is older than this message id"
// @Param limit query int false "At most this many, 50 by default, capped at 200"
// @Success 200 {object} chatutil.ListBranchesResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, or the caller lacks read_messages"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/branches [get]
func listBranches(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	before, _ := strconv.ParseInt(c.Query("before"), 10, 64)
	limit, _ := strconv.ParseInt(c.Query("limit"), 10, 64)
	result, err := chatutil.ListBranches(chatutil.ListBranchesParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal, ChannelID: id,
		Before: before, Limit: limit,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listBranchesRoute = serverutil.ApiRoute("GET", "/chat/channels/:id/branches", listBranches)
