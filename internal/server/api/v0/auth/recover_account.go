package v0_auth

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"

	"github.com/gin-gonic/gin"
)

// recoverAccount godoc
// @Summary Recover account
// @Description Resets the named account's password using its recovery secret: exactly one of recoveryPhrase, the raw phrase of an account that has no recovery key yet, and recoveryKey, the standard base64 of the 32-byte key the client derived from the phrase and the salt GET /auth/salt returned. A wrong key reads exactly like a wrong phrase, and an account with a recovery key refuses every raw phrase. newRecoveryKey, sent only with newAuthKey, gives the account the key of a phrase the client just generated in the same transaction and clears the old phrase, so a legacy recovery is also the account's move to a recovery key (#2430). The body carries exactly one of newPassword and newAuthKey, the standard base64 of the 32-byte key the client derived from the new password and the salt GET /auth/salt returned. Either one replaces both ways of signing in: a new password clears the account's auth key, and a new auth key clears its password. chatKeys, when sent, replaces the account's chat identity in the same transaction: the client fetched it from /auth/recover/keys, opened it with the phrase and re-wrapped it under the new password (#2416). The body is at most 8 KiB.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body recoverAccountBody true "The account, its recovery phrase or key, the new password or auth key, and optionally a new recovery key and its re-wrapped chat keys"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 403 {object} accountRefusal "status is pending or disabled"
// @Router /auth/recover [post]
func recoverAccount(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxKeysRequestBytes)
	var req recoverAccountBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	afterReset, err := storeChatKeys(c.Request.Context(), req.ChatKeys)
	if err != nil {
		return serverutil.BadRequest(err)
	}

	result, err := authutil.Recover(c.Request.Context(), (*deps).Database(), authutil.RecoverParams{
		Username:       req.Username,
		RecoveryPhrase: req.RecoveryPhrase,
		RecoveryKey:    req.RecoveryKey,
		NewRecoveryKey: req.NewRecoveryKey,
		NewPassword:    req.NewPassword,
		NewAuthKey:     req.NewAuthKey,
		SaltSecret:     settingsutil.AuthSaltSecret,
		AfterReset:     afterReset,
	})
	if refusal := accountRefusalResponse(err); refusal != nil {
		return refusal
	}
	if err != nil {
		return serverutil.BadRequest(err)
	}

	if afterReset != nil {
		notifyChatKeyNeeded(c.Request.Context(), *deps)
	}
	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(gin.H{"token": result.SessionToken})
}

var recoverAccountRoute = serverutil.ApiRoute("POST", "/auth/recover", recoverAccount)
