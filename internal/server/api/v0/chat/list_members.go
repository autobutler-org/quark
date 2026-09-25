package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// listMembers godoc
// @Summary List a chat channel's members
// @Description Returns a channel's rows, groups first and then accounts, each by name. A group carries the active accounts in it, everyone's being every active account. Each account carries avatarUpdatedAt (Unix milliseconds) when it has a profile picture, the v parameter for /users/{id}/avatar. Any member of the channel or an admin may list them.
// @Tags chat
// @Produce json
// @Param id path int true "Channel id"
// @Success 200 {object} chatutil.ListMembersResult
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, or the caller isn't a member or an admin"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/members [get]
func listMembers(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.ListMembers(chatutil.ListMembersParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		Principal: principal,
		ChannelID: id,
		DataDir:   storageutil.GetDataDir(),
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listMembersRoute = serverutil.ApiRoute("GET", "/chat/channels/:id/members", listMembers)
