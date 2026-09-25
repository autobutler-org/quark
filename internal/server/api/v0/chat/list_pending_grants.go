package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listPendingGrants godoc
// @Summary List the key grants the caller can fill
// @Description Lists the members, direct or through a group or everyone, who have published chat keys but lack a version of the channel's key that the caller holds, each with the X25519 key to seal it to. Also says whether the key needs rotating. Members only; anyone else gets 404.
// @Tags chat
// @Produce json
// @Param id path int true "Channel id"
// @Success 200 {object} chatutil.ListPendingGrantsResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys/pending [get]
func listPendingGrants(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.ListPendingGrants(chatutil.ListPendingGrantsParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal, ChannelID: id,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listPendingGrantsRoute = serverutil.ApiRoute("GET", "/chat/channels/:id/keys/pending", listPendingGrants)
