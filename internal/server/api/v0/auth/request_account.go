package v0_auth

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"

	"github.com/gin-gonic/gin"
)

// requestAccount godoc
// @Summary Request an account
// @Description Creates a pending account that can sign in once an admin approves it. Needs no session and is rate-limited per IP. A pending request keeps its username taken until it is denied. The body carries authKey, the standard base64 of the 32-byte key the client derived from the password and the salt GET /auth/salt returned, and recoveryKey, the standard base64 of the 32-byte key the client derived from a recovery phrase it generated and the same salt; the Quark makes no phrase, and the response is an empty object. Without recoveryKey the account cannot recover until a sign-in gives it one. A body carrying password, the raw password an app from before auth keys sends, is refused with 426 before anything is checked (#2430).
// @Tags auth
// @Accept json
// @Produce json
// @Param body body newAccountBody true "The username, the authKey and the recoveryKey"
// @Success 201 {object} object
// @Failure 400 {object} serverutil.Response "invalid username, authKey or recoveryKey"
// @Failure 404 {object} serverutil.Response "requests are turned off, or the Quark is not set up"
// @Failure 409 {object} serverutil.Response "that username is taken"
// @Failure 426 {object} serverutil.Response "the body carried a raw password or phrase: the app is too old"
// @Failure 429 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /auth/request-account [post]
func requestAccount(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req newAccountBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	if err := authutil.RefuseRawSecrets(req.Password); err != nil {
		return serverutil.UpgradeRequired(err)
	}

	_, err := authutil.RequestAccount(c.Request.Context(), (*deps).Database().Queries, authutil.RequestAccountParams{
		Username:        req.Username,
		AuthKey:         req.AuthKey,
		RecoveryKey:     req.RecoveryKey,
		SaltSecret:      settingsutil.AuthSaltSecret,
		RequestsEnabled: settingsutil.GetAccessRequestsEnabled(),
	})
	switch {
	case errors.Is(err, authutil.ErrAccessRequestsOff):
		return serverutil.NotFound(err)
	case errors.Is(err, authutil.ErrUsernameTaken):
		return serverutil.Conflict(err)
	case errors.Is(err, authutil.ErrInvalidUsername), errors.Is(err, authutil.ErrInvalidAuthKey),
		errors.Is(err, authutil.ErrInvalidRecoveryKey):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	if bus := (*deps).EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(gin.H{})
}

var requestAccountRoute = serverutil.ApiRoute("POST", "/auth/request-account", requestAccount)
