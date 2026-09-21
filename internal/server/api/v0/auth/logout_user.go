package v0_auth

import (
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// logoutUser godoc
// @Summary Logout
// @Description Invalidates the current session
// @Tags auth
// @Produce json
// @Success 200 {object} object
// @Security BearerAuth
// @Router /auth/logout [post]
func logoutUser(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.Ok()
	}

	token := ""
	if auth := c.GetHeader("Authorization"); len(auth) > 7 && auth[:7] == "Bearer " {
		token = auth[7:]
	} else if cookie, err := c.Cookie(sessionCookieName); err == nil {
		token = cookie
	}

	if token != "" {
		_ = authutil.Logout(c.Request.Context(), (*deps).Database().Queries, token)
	}

	clearSessionCookie(c)
	return serverutil.Ok().WithData(gin.H{"message": "logged out"})
}

var logoutUserRoute = serverutil.ApiRoute("POST", "/auth/logout", logoutUser)
