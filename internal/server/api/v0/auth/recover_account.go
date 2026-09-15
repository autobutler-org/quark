package v0_auth

import (
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// recoverAccount godoc
// @Summary Recover account
// @Description Resets the named account's password using its recovery phrase
// @Tags auth
// @Accept json
// @Produce json
// @Param body body object true "{username, recoveryPhrase, newPassword}"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Router /auth/recover [post]
func recoverAccount(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		Username       string `json:"username" binding:"required"`
		RecoveryPhrase string `json:"recoveryPhrase" binding:"required"`
		NewPassword    string `json:"newPassword" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	result, err := authutil.Recover(c.Request.Context(), (*deps).Database().Queries, authutil.RecoverParams{
		Username:       req.Username,
		RecoveryPhrase: req.RecoveryPhrase,
		NewPassword:    req.NewPassword,
	})
	if err != nil {
		return serverutil.BadRequest(err)
	}

	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(gin.H{"token": result.SessionToken})
}

var recoverAccountRoute = serverutil.ApiRoute("POST", "/auth/recover", recoverAccount)
