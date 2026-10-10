package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listChannels godoc
// @Summary List the caller's chat channels
// @Description Returns the channels the caller is a member of, directly, through a group, or through everyone, general first and then by name, each with the caller's effective permissions there: the union of every row that reaches them, and unreadCount: the messages after the caller's read marker (PUT /chat/channels/{id}/read) that someone else wrote and nobody deleted, 0 on a channel the caller lacks read_messages on. A channel on which that set is empty is left out. Admins get only their own channels too, unless they pass all=1: then the channels they are not in follow, in the same order, with an empty set.
// @Tags chat
// @Produce json
// @Param all query string false "1 adds the channels an admin is not in; refused for anyone else"
// @Success 200 {object} chatutil.ListChannelsResult
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "all=1 from an account that isn't an admin"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels [get]
func listChannels(c *gin.Context) *serverutil.Response {
	deps, principal, failed := requestContext(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		Principal: principal,
		All:       c.Query("all") == "1",
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listChannelsRoute = serverutil.ApiRoute("GET", "/chat/channels", listChannels)
