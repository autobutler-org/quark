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
// @Description Resets the named account's password using its recoveryKey, the standard base64 of the 32-byte key the client derived from the phrase and the salt GET /auth/salt returned. A wrong key, an unknown username and an account with no recovery key all read as a wrong phrase. newAuthKey, the standard base64 of the 32-byte key the client derived from the new password and the same salt, replaces the account's auth key and clears its password hash. An account GET /auth/salt calls legacyRecovery recovers once with its raw recoveryPhrase in place of recoveryKey, beside newAuthKey and newRecoveryKey, the key of a phrase the client just generated, and optionally recoveryPhraseWords, how many words that phrase had (0 to 64, missing is 0, unknown): the reset stores both keys, the count and clears the phrase and password hashes. An account with a recovery key refuses every phrase as a wrong one. A recoveryPhrase without both new keys, or a newPassword, is what only an app from before auth keys sends, and is refused with 426 (#2430). chatKeys, when sent, replaces the account's chat identity in the same transaction: the client fetched it from /auth/recover/keys, opened it with the phrase and re-wrapped it under the new password (#2416). vaultKey, when sent, likewise replaces the wraps of the account's vault key in the same transaction, fetched from /auth/recover/vault-key and re-wrapped the same way (storing it as the first when the account has none), and publishes vault_changed to the account's sessions (#3459). The body is at most 8 KiB.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body recoverAccountBody true "The account, its recovery key or legacy phrase, the new keys, and optionally its re-wrapped chat keys and vault key"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 403 {object} accountRefusal "status is pending or disabled"
// @Failure 426 {object} serverutil.Response "the body carried newPassword, or a phrase without both new keys: the app is too old"
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
	if err := authutil.RefuseRawSecrets(req.NewPassword); err != nil {
		return serverutil.UpgradeRequired(err)
	}
	afterReset, announce, err := storeRewrappedKeys(c.Request.Context(), *deps, req.ChatKeys, req.VaultKey)
	if err != nil {
		return serverutil.BadRequest(err)
	}

	result, err := authutil.Recover(c.Request.Context(), (*deps).Database(), authutil.RecoverParams{
		Username:               req.Username,
		RecoveryPhrase:         req.RecoveryPhrase,
		RecoveryKey:            req.RecoveryKey,
		NewAuthKey:             req.NewAuthKey,
		NewRecoveryKey:         req.NewRecoveryKey,
		NewRecoveryPhraseWords: req.RecoveryPhraseWords,
		SaltSecret:             settingsutil.AuthSaltSecret,
		AfterReset:             afterReset,
	})
	if refusal := accountRefusalResponse(err); refusal != nil {
		return refusal
	}
	if err != nil {
		return serverutil.BadRequest(err)
	}

	announce()
	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(gin.H{"token": result.SessionToken})
}

var recoverAccountRoute = serverutil.ApiRoute("POST", "/auth/recover", recoverAccount)
