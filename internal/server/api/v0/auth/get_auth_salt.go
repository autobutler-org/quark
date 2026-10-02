package v0_auth

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"

	"github.com/gin-gonic/gin"
)

// getAuthSalt godoc
// @Summary Get the salt for an auth key
// @Description Returns the salt a client derives the named account's auth key with, as the standard base64 of 16 bytes. Needs no session and is rate-limited per IP. A username with no account gets a salt too, the same one every time, so the answer does not say whether the account exists. legacy is true for an account that has no auth key yet: the client signs in with both password and authKey to give it one.
// @Tags auth
// @Produce json
// @Param username query string true "The account's username"
// @Success 200 {object} saltResponse
// @Failure 400 {object} serverutil.Response "no username"
// @Failure 429 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Router /auth/salt [get]
func getAuthSalt(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.InternalServerError(nil)
	}
	username := c.Query("username")
	if username == "" {
		return serverutil.BadRequest(errors.New("username is required"))
	}

	result, err := authutil.GetSalt(c.Request.Context(), (*deps).Database().Queries, authutil.GetSaltParams{
		Username:   username,
		SaltSecret: settingsutil.AuthSaltSecret,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(saltResponse{Salt: result.Salt, Legacy: result.Legacy})
}

var getAuthSaltRoute = serverutil.ApiRoute("GET", "/auth/salt", getAuthSalt)
