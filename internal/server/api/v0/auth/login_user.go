package v0_auth

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"

	"github.com/gin-gonic/gin"
)

// loginUser godoc
// @Summary Login
// @Description Authenticates and returns a session token. The body takes one of three shapes: {username, password} checks the password; {username, authKey} checks the key the client derived from the password and the salt GET /auth/salt returned, and is a 401 for an account that has no auth key yet; {username, password, authKey} checks the password and gives an account with no auth key that one, keeping its password. authKey is the standard base64 of 32 bytes. On the first sign-in of an account an admin created, the response also carries recoveryPhrase, which is never returned again. A pending or disabled account with the right password gets 403 with its status, so the app can tell it from a wrong password.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body credentialsBody true "The username with a password, an authKey, or both"
// @Success 200 {object} loginResponse
// @Failure 400 {object} serverutil.Response "no password or authKey, or a malformed authKey"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} accountRefusal "status is pending or disabled"
// @Router /auth/login [post]
func loginUser(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req credentialsBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	result, err := authutil.Login(c.Request.Context(), (*deps).Database().Queries, authutil.LoginParams{
		Username:   req.Username,
		Password:   req.Password,
		AuthKey:    req.AuthKey,
		SaltSecret: settingsutil.AuthSaltSecret,
	})
	if refusal := accountRefusalResponse(err); refusal != nil {
		return refusal
	}
	if errors.Is(err, authutil.ErrCredentialRequired) || errors.Is(err, authutil.ErrInvalidAuthKey) {
		return serverutil.BadRequest(err)
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
