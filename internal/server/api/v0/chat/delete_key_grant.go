package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// deleteKeyGrant godoc
// @Summary Reject your own key grant
// @Description Deletes the caller's own grant of one version of the channel key, for a grant the caller's app couldn't open or verify. Grants are first-write-wins, so this is how a recipient clears a useless one. The caller is pending again, and the key holders hear chat_key_needed so one of them refills it. Only the recipient can delete a grant.
// @Tags chat
// @Produce json
// @Param id path int true "Channel id"
// @Param version path int true "Key version"
// @Success 200 {object} chatutil.RejectGrantResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, the caller isn't a member, or holds no grant of that version"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys/grants/{version} [delete]
func deleteKeyGrant(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	version, err := strconv.ParseInt(c.Param("version"), 10, 64)
	if err != nil || version <= 0 {
		return serverutil.NotFound(chatutil.ErrGrantNotFound)
	}
	result, err := chatutil.RejectGrant(chatutil.RejectGrantParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(),
		Principal: principal, ChannelID: id, Version: version,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var deleteKeyGrantRoute = serverutil.ApiRoute("DELETE", "/chat/channels/:id/keys/grants/:version", deleteKeyGrant)
