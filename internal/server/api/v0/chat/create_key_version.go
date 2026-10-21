package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// createKeyVersion godoc
// @Summary Create the next version of a chat channel's key
// @Description Starts a channel's key (version 1) or rotates it once rotationNeeded is true, storing the caller's own grant of the new key: sealedKey is the 80-byte crypto_box_seal of the key to the caller's X25519 key and signature the caller's 64-byte Ed25519 signature over the grant, both base64. The caller then fills the other members' grants. Any member with published chat keys may do it. Returns the key_created event for the caller to sign. Publishes chat_key_needed to key holders when members lack the new version.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body createKeyVersionBody true "The version and the caller's grant of it"
// @Success 200 {object} chatutil.CreateKeyVersionResult
// @Failure 400 {object} serverutil.Response "a sealed key or signature of the wrong size, or a signature that doesn't verify against the caller's chat keys"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such channel, the caller isn't a member, or has no chat keys"
// @Failure 409 {object} serverutil.Response "version isn't the next one (another member created it first), or the key doesn't need rotating"
// @Failure 429 {object} serverutil.Response "the caller sent too many of these in a short time; the limit is per account"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys [post]
func createKeyVersion(c *gin.Context) *serverutil.Response {
	return newKeyVersion(c, false)
}

var createKeyVersionRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/keys", createKeyVersion)
