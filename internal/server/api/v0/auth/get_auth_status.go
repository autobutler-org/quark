package v0_auth

import (
	"strings"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getAuthStatus godoc
// @Summary Check auth setup status
// @Description Returns whether initial setup has been completed. For a caller with a valid session it also returns that caller's username and isAdmin flag.
// @Tags auth
// @Produce json
// @Success 200 {object} object
// @Router /auth/status [get]
func getAuthStatus(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok || (*deps).Database() == nil {
		return serverutil.Ok().WithData(gin.H{"setup": false})
	}

	// The status route is exempt from requireAuth, so nothing has identified
	// the caller yet. Read the same session credentials it would.
	token := strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer ")
	if token == c.GetHeader("Authorization") {
		token, _ = c.Cookie("session")
	}

	status, err := authutil.GetAuthStatus(c.Request.Context(), (*deps).Database().Queries, authutil.GetAuthStatusParams{
		SessionToken: token,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !status.Authenticated {
		return serverutil.Ok().WithData(gin.H{"setup": status.Setup})
	}
	return serverutil.Ok().WithData(gin.H{
		"setup":    status.Setup,
		"username": status.Username,
		"isAdmin":  status.IsAdmin,
	})
}

var getAuthStatusRoute = serverutil.ApiRoute("GET", "/auth/status", getAuthStatus)
