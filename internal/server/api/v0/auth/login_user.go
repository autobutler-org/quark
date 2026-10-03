package v0_auth

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"

	"github.com/gin-gonic/gin"
)

// loginUser godoc
// @Summary Login
// @Description Authenticates with {username, authKey} and returns a session token. authKey is the standard base64 of the 32-byte key the client derived from the password and the salt GET /auth/salt returned. {username, password, authKey} is the one-time upgrade of an account GET /auth/salt calls legacy: the password is checked against the stored one, and the key, its salt and a cleared password hash are stored in one write, so the password never signs in again; a failed write refuses the sign-in with 500. An account that already has an auth key is checked by the key, and the password beside it is ignored. A body carrying password with no authKey, which only an app from before auth keys sends, is refused with 426 before anything is checked (#2430). legacyRecovery is true for an account that has no recovery key yet, such as one an admin created: the client generates a phrase and sends its key to PUT /auth/recovery-key. A pending or disabled account with the right key gets 403 with its status, so the app can tell it from a wrong password. Repeated failures lock out the client address, the account at that address, or the account from new addresses for a while: the answer is 429 with Retry-After in seconds, whether or not the username exists.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body credentialsBody true "The username, the authKey, and for the upgrade the password"
// @Success 200 {object} loginResponse
// @Failure 400 {object} serverutil.Response "a missing or malformed authKey"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} accountRefusal "status is pending or disabled"
// @Failure 426 {object} serverutil.Response "the body carried a password with no authKey: the app is too old"
// @Failure 500 {object} serverutil.Response "the upgrade's write failed"
// @Failure 429 {object} serverutil.Response "locked out after repeated failures; see Retry-After"
// @Header 429 {integer} Retry-After "seconds until the lockout lifts"
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
		Guard:      (*deps).LoginGuard(),
		ClientIP:   ratelimitutil.ExtractIP(c.ClientIP()),
	})
	if locked := lockoutResponse(c, err); locked != nil {
		return locked
	}
	if refusal := accountRefusalResponse(err); refusal != nil {
		return refusal
	}
	if errors.Is(err, authutil.ErrInvalidAuthKey) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.NewResponse().WithStatusCode(http.StatusUnauthorized).WithError(err)
	}

	setSessionCookie(c, result.SessionToken)
	return serverutil.Ok().WithData(loginResponse{
		Token:          result.SessionToken,
		LegacyRecovery: result.LegacyRecovery,
	})
}

var loginUserRoute = serverutil.ApiRoute("POST", "/auth/login", loginUser)
