package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// setMember godoc
// @Summary Add a chat channel member or change its level
// @Description Gives one active account or existing group read, write or owner on a channel, replacing the level it had, and returns the channel's members as they now stand. Only an owner of the channel or an admin may. Publishes chat_channel_changed to everyone who was or now is a member.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body setMemberBody true "One account or group, and the level"
// @Success 200 {object} chatutil.ListMembersResult
// @Failure 400 {object} serverutil.Response "not exactly one account or group, or a level other than read, write or owner, or demoting the last owner when the caller is not an admin"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller is a member but not an owner"
// @Failure 404 {object} serverutil.Response "no such channel, the caller isn't a member or an admin, or no active account or group has that id"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/members [put]
func setMember(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	var body setMemberBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(accessutil.ErrGrantTarget)
	}
	result, err := chatutil.SetMember(chatutil.SetMemberParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		ChannelID: id,
		UserID:    body.UserID,
		GroupID:   body.GroupID,
		Level:     accessutil.ParseLevel(body.Level),
		DataDir:   storageutil.GetDataDir(),
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var setMemberRoute = serverutil.ApiRoute("PUT", "/chat/channels/:id/members", setMember)
