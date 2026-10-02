package v0_auth

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// recoverChatKeys godoc
// @Summary Fetch chat keys for account recovery
// @Description The first step of recovering an account that has chat keys (#2416). Checks the recovery phrase or recovery key exactly as /auth/recover does, changes nothing, and returns the account's wrapped chat identity so the client can open it with the phrase wrap key and send it back re-wrapped under the new password in /auth/recover. Needs no session and shares the sign-in rate limit. The body carries exactly one of recoveryPhrase and recoveryKey (#2430). An unknown username or a wrong key reads as a wrong phrase.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body recoverChatKeysBody true "The account and its recovery phrase or recovery key"
// @Success 200 {object} chatutil.Keys
// @Failure 400 {object} serverutil.Response "a wrong phrase or key, an unknown username, a malformed key, or neither or both secrets"
// @Failure 403 {object} accountRefusal "status is pending or disabled"
// @Failure 404 {object} serverutil.Response "the account has no chat keys yet"
// @Failure 429 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /auth/recover/keys [post]
func recoverChatKeys(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	var req recoverChatKeysBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	queries := (*deps).Database().Queries
	checked, err := authutil.CheckRecovery(c.Request.Context(), queries, authutil.CheckRecoveryParams{
		Username:       req.Username,
		RecoveryPhrase: req.RecoveryPhrase,
		RecoveryKey:    req.RecoveryKey,
	})
	if refusal := accountRefusalResponse(err); refusal != nil {
		return refusal
	}
	if err != nil {
		return serverutil.BadRequest(err)
	}
	result, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: c.Request.Context(), Queries: queries, UserID: checked.UserID})
	if errors.Is(err, chatutil.ErrKeysNotFound) {
		return serverutil.NewResponse().WithStatusCode(http.StatusNotFound).WithError(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result.Keys)
}

var recoverChatKeysRoute = serverutil.ApiRoute("POST", "/auth/recover/keys", recoverChatKeys)
