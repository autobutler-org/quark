package v0_auth

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// setRecoveryKey godoc
// @Summary Set the caller's recovery key
// @Description Re-confirms the caller with password, which carries the auth key, exactly as DELETE /auth/account takes it; a wrong or missing key is a 403, a raw password is a 426, and nothing is written. Then gives the signed-in account the recovery key its client derived from a recovery phrase the client generated, (#2430). recoveryKey is the standard base64 of the 32-byte key derived from the phrase and the salt GET /auth/salt returned. chatKeys, when sent, replaces the account's chat identity in the same transaction, re-wrapped under the new phrase, exactly as /auth/recover stores it; nothing changes if any part fails. The client calls this after a sign-in whose response says legacyRecovery, such as the first sign-in of an account an admin created. Shares the sign-in rate limit, and the body is at most 8 KiB.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body setRecoveryKeyBody true "The caller's auth key, the new recovery key and optionally the re-wrapped chat keys"
// @Success 204
// @Failure 400 {object} serverutil.Response "a malformed recoveryKey or chatKeys"
// @Failure 401 {object} serverutil.Response "no session, or the session's account no longer exists"
// @Failure 403 {object} serverutil.Response "the auth key is wrong or missing"
// @Failure 409 {object} serverutil.Response "the account has no auth key yet, so no salt to derive the key with"
// @Failure 426 {object} serverutil.Response "password is a raw password: the app is too old"
// @Failure 429 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /auth/recovery-key [put]
func setRecoveryKey(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	userID, ok := ctxutil.Get[int64](c, "userID")
	username, hasName := ctxutil.Get[string](c, "username")
	if !ok || userID == 0 || !hasName || username == "" {
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	}

	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, chatutil.MaxKeysRequestBytes)
	var req setRecoveryKeyBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	// Checked before anything is written: a stolen session must not be able to
	// swap the recovery credential for one the thief holds.
	_, err := authutil.VerifyPassword(c.Request.Context(), authutil.VerifyPasswordParams{
		Queries:  (*deps).Database().Queries,
		Username: username,
		Password: req.Password,
	})
	if errors.Is(err, authutil.ErrIncorrectPassword) {
		return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithError(err)
	}
	if errors.Is(err, authutil.ErrUserNotFound) {
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	afterSet, err := storeChatKeys(c.Request.Context(), req.ChatKeys)
	if err != nil {
		return serverutil.BadRequest(err)
	}

	_, err = authutil.SetRecoveryKey(c.Request.Context(), (*deps).Database(), authutil.SetRecoveryKeyParams{
		UserID:      userID,
		RecoveryKey: req.RecoveryKey,
		AfterSet:    afterSet,
	})
	switch {
	case errors.Is(err, authutil.ErrInvalidRecoveryKey):
		return serverutil.BadRequest(err)
	case errors.Is(err, authutil.ErrNoAuthSalt):
		return serverutil.Conflict(err)
	case errors.Is(err, authutil.ErrUserNotFound):
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	if afterSet != nil {
		notifyChatKeyNeeded(c.Request.Context(), *deps)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusNoContent)
}

var setRecoveryKeyRoute = serverutil.ApiRoute("PUT", "/auth/recovery-key", setRecoveryKey)
