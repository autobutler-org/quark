package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// setMember godoc
// @Summary Add a chat channel member or change its permissions
// @Description Gives one active account or existing group a set of permissions on a channel, replacing the set its row had, and returns the channel's members as they now stand. Needs manage_members, or an admin. A caller may grant only permissions they hold, and may take permissions away only from a principal whose effective set is a strict subset of theirs unless they hold manage_channel; only an admin may demote the channel's creator. everyone keeps read_messages on general. Publishes chat_channel_changed to everyone who was or now is a member.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body setMemberBody true "One account or group, and its permissions"
// @Success 200 {object} chatutil.ListMembersResult
// @Failure 400 {object} serverutil.Response "not exactly one account or group, everyone below read_messages on general, or leaving the channel without a manage_channel holder when the caller is not an admin"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller lacks manage_members, grants a permission they lack, or demotes someone they may not"
// @Failure 404 {object} serverutil.Response "no such channel, the caller's set on it is empty and they aren't an admin, or no active account or group has that id"
// @Failure 422 {object} serverutil.Response "an unknown permission, an empty set, or a message permission without read_messages"
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
	permissions, err := chatutil.ParsePerms(body.Permissions)
	if err != nil {
		return chatError(err)
	}
	result, err := chatutil.SetMember(chatutil.SetMemberParams{
		Ctx:         c.Request.Context(),
		Database:    deps.Database(),
		EventBus:    deps.EventBus(),
		Principal:   principal,
		ChannelID:   id,
		UserID:      body.UserID,
		GroupID:     body.GroupID,
		Permissions: permissions,
		DataDir:     storageutil.GetDataDir(),
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var setMemberRoute = serverutil.ApiRoute("PUT", "/chat/channels/:id/members", setMember)
