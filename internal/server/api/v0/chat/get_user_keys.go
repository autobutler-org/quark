package v0_chat

import (
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getUserKeys godoc
// @Summary Get an account's public chat keys
// @Description Returns an active account's X25519 box and Ed25519 signing public keys, base64, and never its wrapped private seeds. Any signed-in account may ask. 404 means the account doesn't exist, isn't active, or has no chat keys yet.
// @Tags chat
// @Produce json
// @Param userId path int true "Account id"
// @Success 200 {object} chatutil.PublicKeys
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such active account, or it has no chat keys yet"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/keys/{userId} [get]
func getUserKeys(c *gin.Context) *serverutil.Response {
	deps, _, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	userID, err := strconv.ParseInt(c.Param("userId"), 10, 64)
	if err != nil || userID <= 0 {
		return serverutil.NotFound(chatutil.ErrKeysNotFound)
	}
	result, err := chatutil.GetPublicKeys(chatutil.GetPublicKeysParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  userID,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.PublicKeys)
}

var getUserKeysRoute = serverutil.ApiRoute("GET", "/chat/keys/:userId", getUserKeys)
