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
// @Description Removes one account's or group's row from a channel and returns the channel's members as they now stand. Any member may remove their own account's row, which is leaving. Removing anyone else needs manage_members and a target whose effective set is a strict subset of the caller's, unless the caller holds manage_channel; only an admin may remove the channel's creator or skip those rules. everyone can't be removed from general. Publishes chat_channel_changed to everyone who was or now is a member.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body removeMemberBody true "One account or group"
// @Success 200 {object} chatutil.ListMembersResult
// @Failure 400 {object} serverutil.Response "not exactly one account or group, or everyone on general"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "removing someone else without manage_members, or someone the caller may not remove"
// @Failure 404 {object} serverutil.Response "no such channel, the caller's set on it is empty and they aren't an admin, or the account or group has no row"
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
