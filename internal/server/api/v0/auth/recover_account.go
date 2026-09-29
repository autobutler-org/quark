package v0_auth

import (
	"net/http"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// recoverAccount godoc
// @Summary Recover account
// @Description Resets the named account's password using its recovery phrase. chatKeys, when sent, replaces the account's chat identity in the same transaction: the client fetched it from /auth/recover/keys, opened it with the phrase and re-wrapped it under the new password (#2416). The body is at most 8 KiB.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body recoverAccountBody true "The account, its recovery phrase, the new password and optionally its re-wrapped chat keys"
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
	var afterReset func(*db.Queries, int64) error
	if req.ChatKeys != nil {
		if err := chatutil.ValidateKeys(*req.ChatKeys); err != nil {
			return serverutil.BadRequest(err)
		}
		afterReset = func(q *db.Queries, userID int64) error {
			_, err := chatutil.PutKeys(chatutil.PutKeysParams{
				Ctx:     c.Request.Context(),
				Queries: q,
				UserID:  userID,
				Keys:    *req.ChatKeys,
			})
			return err
		}
	}

	result, err := authutil.Recover(c.Request.Context(), (*deps).Database(), authutil.RecoverParams{
		Username:       req.Username,
		RecoveryPhrase: req.RecoveryPhrase,
		NewPassword:    req.NewPassword,
		AfterReset:     afterReset,
	})
	if refusal := accountRefusalResponse(err); refusal != nil {
		return refusal
	}
	if err != nil {
		return serverutil.BadRequest(err)
	}

	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(gin.H{"token": result.SessionToken})
}

var recoverAccountRoute = serverutil.ApiRoute("POST", "/auth/recover", recoverAccount)
