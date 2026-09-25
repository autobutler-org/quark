package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// listChannels godoc
// @Summary List the caller's chat channels
// @Description Returns the channels the caller is a member of, directly, through a group, or through everyone, general first and then by name, each with the caller's best level: read, write or owner. Admins get only their own channels too.
// @Tags chat
// @Produce json
// @Success 200 {object} chatutil.ListChannelsResult
// @Failure 401 {object} serverutil.Response
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
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listChannelsRoute = serverutil.ApiRoute("GET", "/chat/channels", listChannels)
