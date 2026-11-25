package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// putMyChannelKeys godoc
// @Summary Publish the caller's keys for an anonymous chat channel
// @Description Stores the X25519 and Ed25519 public keys (32 bytes each, base64) the caller's app derived for one anonymous channel (#2949), against the caller's pseudonym there, made if they have none, and returns that pseudonym. In an anonymous channel grants are sealed to these keys and grants and events are checked against them, never the account's. Publishing the keys already stored does nothing; other keys are refused until the caller's chat identity changes, which clears them. Anyone the channel's rows give a set may publish, and an admin in any channel but a direct message. Publishes chat_key_needed to the channel's key holders.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body putMyChannelKeysBody true "The caller's public keys for this channel"
// @Success 200 {object} chatutil.PutChannelKeysResult
// @Failure 400 {object} serverutil.Response "keys of the wrong size, or a channel that isn't anonymous"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, or the caller's set on it is empty and they aren't an admin"
// @Failure 409 {object} serverutil.Response "the caller already published other keys for this channel"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys/me [put]
func putMyChannelKeys(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	var body putMyChannelKeysBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidKeys)
	}
	result, err := chatutil.PutChannelKeys(chatutil.PutChannelKeysParams{
		Ctx:           c.Request.Context(),
		Database:      deps.Database(),
		EventBus:      deps.EventBus(),
		Principal:     principal,
		ChannelID:     id,
		BoxPublicKey:  body.BoxPublicKey,
		SignPublicKey: body.SignPublicKey,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var putMyChannelKeysRoute = serverutil.ApiRoute("PUT", "/chat/channels/:id/keys/me", putMyChannelKeys)
