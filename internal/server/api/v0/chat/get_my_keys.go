package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getMyKeys godoc
// @Summary Get the caller's chat identity
// @Description Returns the caller's chat public keys and the private seeds wrapped on the client under the login password and, when present, the recovery phrase. Byte fields are base64. The Quark never opens them. 404 means the caller has no chat keys yet and the client should generate them.
// @Tags chat
// @Produce json
// @Success 200 {object} chatutil.Keys
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "the caller has no chat keys yet"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/keys/me [get]
func getMyKeys(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.GetKeys(chatutil.GetKeysParams{
		Ctx:     c.Request.Context(),
		Queries: deps.Database().Queries,
		UserID:  principal.UserID,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.Ok().WithData(result.Keys)
}

var getMyKeysRoute = serverutil.ApiRoute("GET", "/chat/keys/me", getMyKeys)
