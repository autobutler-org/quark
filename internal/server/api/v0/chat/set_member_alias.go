package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// setMemberAlias godoc
// @Summary Set a member's alias in an anonymous chat channel
// @Description Renames the pseudonym one account goes by in an anonymous channel (#2949) and returns the channel's members as they now stand, as the member list shows them to the caller: real accounts included for a holder of manage_members or an admin. The account is named by its id or its pseudonym, and must be one the channel's rows reach or one that already has a pseudonym there. Any member may rename themselves; renaming anyone else needs manage_members, or an admin. The alias is trimmed, has 1 to 32 characters and no line breaks or tabs, and is unique in the channel and no account's username, in any case. Publishes chat_channel_changed to the channel's members.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body setMemberAliasBody true "The account, by id or pseudonym, and its new alias"
// @Success 200 {object} chatutil.ListMembersResult
// @Failure 400 {object} serverutil.Response "an invalid alias, a channel that isn't anonymous, or a direct message"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller names someone other than themselves and lacks manage_members"
// @Failure 404 {object} serverutil.Response "no such channel, the caller's set on it is empty and they aren't an admin, or the account isn't in the channel"
// @Failure 409 {object} serverutil.Response "someone else in the channel goes by that alias, or it is an account's username, in any case"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/members/alias [put]
func setMemberAlias(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	var body setMemberAliasBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidAlias)
	}
	result, err := chatutil.SetAlias(chatutil.SetAliasParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		ChannelID: id,
		UserID:    body.UserID,
		Alias:     body.Alias,
		DataDir:   storageutil.GetDataDir(),
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var setMemberAliasRoute = serverutil.ApiRoute("PUT", "/chat/channels/:id/members/alias", setMemberAlias)
