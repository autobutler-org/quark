package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listChannelEvents godoc
// @Summary List a chat channel's system events
// @Description Pages the channel's membership and key events oldest first: member_set, member_removed and key_created. Each has the JSON payload its signature covers; signature and signerSignKey are absent until the actor's client signs it, and an unsigned event is shown as unverified. Members only; anyone else gets 404.
// @Tags chat
// @Produce json
// @Param id path int true "Channel id"
// @Param after query int false "The last event id already seen"
// @Param limit query int false "At most this many, capped at 200"
// @Success 200 {object} chatutil.ListEventsResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/events [get]
func listChannelEvents(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	after, _ := strconv.ParseInt(c.Query("after"), 10, 64)
	limit, _ := strconv.ParseInt(c.Query("limit"), 10, 64)
	result, err := chatutil.ListEvents(chatutil.ListEventsParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal, ChannelID: id, After: after, Limit: limit,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listChannelEventsRoute = serverutil.ApiRoute("GET", "/chat/channels/:id/events", listChannelEvents)
