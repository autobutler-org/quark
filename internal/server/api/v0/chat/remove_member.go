package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// removeMember godoc
// @Summary Remove a chat channel member
// @Description Removes one account's or group's row from a channel and returns the channel's members as they now stand. An owner of the channel or an admin may remove any row, and any member may remove their own account's row, which is leaving. everyone can't be removed from general. Publishes chat_channel_changed to everyone who was or now is a member.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body removeMemberBody true "One account or group"
// @Success 200 {object} chatutil.ListMembersResult
// @Failure 400 {object} serverutil.Response "not exactly one account or group, everyone on general, or the last owner when the caller is not an admin"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller is a member but not an owner, removing someone else"
// @Failure 404 {object} serverutil.Response "no such channel, the caller isn't a member or an admin, or the account or group has no row"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/members [delete]
func removeMember(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	var body removeMemberBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(accessutil.ErrGrantTarget)
	}
	result, err := chatutil.RemoveMember(chatutil.RemoveMemberParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		ChannelID: id,
		UserID:    body.UserID,
		GroupID:   body.GroupID,
		DataDir:   storageutil.GetDataDir(),
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var removeMemberRoute = serverutil.ApiRoute("DELETE", "/chat/channels/:id/members", removeMember)
