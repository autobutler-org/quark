package v0_auth

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// loginUser godoc
// @Summary Login
// @Description Authenticates with username and password, returns a session token. On the first sign-in of an account an admin created, the response also carries recoveryPhrase, which is never returned again. A pending or disabled account with the right password gets 403 with its status, so the app can tell it from a wrong password.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body object true "{username, password}"
// @Success 200 {object} loginResponse
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} accountRefusal "status is pending or disabled"
// @Router /auth/login [post]
func loginUser(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	result, err := authutil.Login(c.Request.Context(), (*deps).Database().Queries, authutil.LoginParams{
		Username: req.Username,
		Password: req.Password,
	})
	if refusal := accountRefusalResponse(err); refusal != nil {
		return refusal
	}
	if err != nil {
		return serverutil.NewResponse().WithStatusCode(http.StatusUnauthorized).WithError(err)
	}

	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(loginResponse{
		Token:          result.SessionToken,
		RecoveryPhrase: result.RecoveryPhrase,
	})
}

var loginUserRoute = serverutil.ApiRoute("POST", "/auth/login", loginUser)
