package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// regenerateKeyVersion godoc
// @Summary Regenerate a chat channel's key
// @Description Creates the next version of a channel's key even when rotationNeeded is false, storing the caller's own grant of the new key: sealedKey is the 80-byte crypto_box_seal of the key to the caller's X25519 key and signature the caller's 64-byte Ed25519 signature over the grant, both base64. The caller then fills the other members' grants, so a channel stuck on an offline holder can open. Admin only, and the admin must already hold read_messages: another member gets 403, and anyone without read_messages gets 404. Returns the key_created event for the caller to sign. Shares the key-version rate limit. Publishes chat_key_needed to key holders when members lack the new version.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body createKeyVersionBody true "The version and the caller's grant of it"
// @Success 200 {object} chatutil.CreateKeyVersionResult
// @Failure 400 {object} serverutil.Response "a sealed key or signature of the wrong size, or a signature that doesn't verify against the caller's chat keys"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller holds read_messages but is not an admin"
// @Failure 404 {object} serverutil.Response "no such channel, the caller isn't a member, or has no chat keys"
// @Failure 409 {object} serverutil.Response "version isn't the next one (another member created it first)"
// @Failure 429 {object} serverutil.Response "the caller sent too many key versions in a short time; the limit is per account and shared with creating one"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys/regenerate [post]
func regenerateKeyVersion(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	// The same bucket as POST /keys (#2485): regenerating is another way to
	// mint a version, and an admin must not bury the channel under them.
	if limited := rateLimited(deps, principal, "keys"); limited != nil {
		return limited
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
		Ctx:        c.Request.Context(),
		Database:   deps.Database(),
		EventBus:   deps.EventBus(),
		Principal:  principal,
		ChannelID:  id,
		Version:    body.Version,
		SealedKey:  body.SealedKey,
		Signature:  body.Signature,
		Regenerate: true,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result)
}

var regenerateKeyVersionRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/keys/regenerate", regenerateKeyVersion)
