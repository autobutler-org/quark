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
// @Description Creates a pending account that can sign in once an admin approves it, and returns its recovery phrase this once. Needs no session and is rate-limited per IP. A pending request keeps its username taken until it is denied.
// @Tags auth
// @Accept json
// @Produce json
// @Param body body requestAccountBody true "The username and password to request"
// @Success 201 {object} requestAccountResponse
// @Failure 400 {object} serverutil.Response "invalid username or password"
// @Failure 404 {object} serverutil.Response "requests are turned off, or the Quark is not set up"
// @Failure 409 {object} serverutil.Response "that username is taken"
// @Failure 429 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /auth/request-account [post]
func requestAccount(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req requestAccountBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	result, err := authutil.RequestAccount(c.Request.Context(), (*deps).Database().Queries, authutil.RequestAccountParams{
		Username:        req.Username,
		Password:        req.Password,
		RequestsEnabled: settingsutil.GetAccessRequestsEnabled(),
	})
	switch {
	case errors.Is(err, authutil.ErrAccessRequestsOff):
		return serverutil.NotFound(err)
	case errors.Is(err, authutil.ErrUsernameTaken):
		return serverutil.Conflict(err)
	case errors.Is(err, authutil.ErrInvalidUsername), errors.Is(err, authutil.ErrPasswordTooShort):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	if bus := (*deps).EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(requestAccountResponse{
		RecoveryPhrase: result.RecoveryPhrase,
	})
}

var requestAccountRoute = serverutil.ApiRoute("POST", "/auth/request-account", requestAccount)
