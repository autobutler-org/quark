package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// createKeyVersion godoc
// @Summary Create the next version of a chat channel's key
// @Description Starts a channel's key (version 1) or rotates it, storing the caller's own grant of the new key: sealedKey is the 80-byte crypto_box_seal of the key to the caller's X25519 key and signature the caller's 64-byte Ed25519 signature over the grant, both base64. The caller then fills the other members' grants. Any member with published chat keys may do it. Returns the key_created event for the caller to sign. Publishes chat_key_needed to key holders when members lack the new version.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body createKeyVersionBody true "The version and the caller's grant of it"
// @Success 200 {object} chatutil.CreateKeyVersionResult
// @Failure 400 {object} serverutil.Response "a sealed key or signature of the wrong size"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, the caller isn't a member, or has no chat keys"
// @Failure 409 {object} serverutil.Response "version isn't the next one; another member created it first"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys [post]
func createKeyVersion(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxKeysRequestBytes)
	var body createKeyVersionBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidGrant)
	}
	result, err := chatutil.CreateKeyVersion(chatutil.CreateKeyVersionParams{
		Ctx:       c.Request.Context(),
		Database:  deps.Database(),
		EventBus:  deps.EventBus(),
		Principal: principal,
		ChannelID: id,
		Version:   body.Version,
		SealedKey: body.SealedKey,
		Signature: body.Signature,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var createKeyVersionRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/keys", createKeyVersion)
