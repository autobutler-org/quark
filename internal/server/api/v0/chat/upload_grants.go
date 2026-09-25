package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// uploadGrants godoc
// @Summary Upload key grants for other members
// @Description Stores up to 256 grants, each a version of the channel key the caller holds, sealed (80 bytes) to a member with published chat keys and signed (64 bytes) by the caller, base64. The first grant for a member and version wins: a later one is ignored and the stored one returned. Publishes chat_key_granted to the recipients.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body uploadGrantsBody true "The grants"
// @Success 200 {object} chatutil.UploadGrantsResult
// @Failure 400 {object} serverutil.Response "a malformed grant, or one for someone who isn't a member with chat keys"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller holds no grant for that version"
// @Failure 404 {object} serverutil.Response "no such channel, the caller isn't a member, or has no chat keys"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys/grants [post]
func uploadGrants(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxGrantsRequestBytes)
	var body uploadGrantsBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidGrant)
	}
	result, err := chatutil.UploadGrants(chatutil.UploadGrantsParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		ChannelID: id,
		Grants:    body.Grants,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var uploadGrantsRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/keys/grants", uploadGrants)
