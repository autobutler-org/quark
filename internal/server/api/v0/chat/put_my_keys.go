package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// putMyKeys godoc
// @Summary Create or replace the caller's chat identity
// @Description Stores the caller's chat public keys (32 bytes each) and private seeds wrapped on the client (at most 512 bytes each), with 16-byte Argon2id salts and the client's kdfParams object. wrappedByPhrase and saltRp are both present or both absent. Byte fields are base64 and the body is at most 8 KiB. Replaces any keys the caller had.
// @Tags chat
// @Accept json
// @Produce json
// @Param body body chatutil.Keys true "The caller's chat identity; createdAt and updatedAt are ignored"
// @Success 200 {object} chatutil.Keys
// @Failure 400 {object} serverutil.Response "keys of the wrong size or shape, or a body over 8 KiB"
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/keys/me [put]
func putMyKeys(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxKeysRequestBytes)
	var body chatutil.Keys
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(chatutil.ErrInvalidKeys)
	}
	result, err := chatutil.PutKeys(chatutil.PutKeysParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  principal.UserID,
		Keys:    body,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Keys)
}

var putMyKeysRoute = serverutil.ApiRoute("PUT", "/chat/keys/me", putMyKeys)
