package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// regenerateKeyVersion godoc
// @Summary Regenerate a chat channel's key as an admin
// @Description Creates the next version of a channel's key even though rotationNeeded is false, for an admin who holds read_messages but no grant of the current version: the members holding it are away, and the others wait on them (#3455). The body is POST /keys': the version and the caller's own grant, base64. The caller then fills every other member's grant. The key_created event's payload carries "regenerated": true, for the caller to sign. Shares POST /keys' rate limit. Messages under older versions still need a holder of those to share them.
// @Tags chat
// @Accept json
// @Produce json
// @Param id path int true "Channel id"
// @Param body body createKeyVersionBody true "The version and the caller's grant of it"
// @Success 200 {object} chatutil.CreateKeyVersionResult
// @Failure 400 {object} serverutil.Response "a sealed key or signature of the wrong size, or a signature that doesn't verify against the caller's chat keys"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller isn't an admin"
// @Failure 404 {object} serverutil.Response "no such channel, the caller doesn't hold read_messages on it, or has no chat keys"
// @Failure 409 {object} serverutil.Response "version isn't the next one, or the caller already holds the current version"
// @Failure 429 {object} serverutil.Response "the caller sent too many of these in a short time; the limit is per account"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/keys/regenerate [post]
func regenerateKeyVersion(c *gin.Context) *serverutil.Response {
	return newKeyVersion(c, true)
}

var regenerateKeyVersionRoute = serverutil.ApiRoute("POST", "/chat/channels/:id/keys/regenerate", regenerateKeyVersion)
