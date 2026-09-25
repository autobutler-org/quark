package v0_auth

import (
	"log/slog"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/avatarutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// getAuthStatus godoc
// @Summary Check auth setup status
// @Description Returns whether initial setup has been completed and, once it has, accessRequestsEnabled: whether the sign-in page may offer to request an account, and chatEnabled: whether the chat beta is on. For a caller with a valid session it also returns that caller's username, userId and isAdmin flag, and avatarUpdatedAt (Unix milliseconds) when they have a profile picture.
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
	body := gin.H{"setup": status.Setup}
	if status.Setup {
		body["accessRequestsEnabled"] = settingsutil.GetAccessRequestsEnabled()
		body["chatEnabled"] = settingsutil.GetChatEnabled()
	}
	if status.Authenticated {
		body["username"] = status.Username
		body["userId"] = status.UserID
		body["isAdmin"] = status.IsAdmin
		// Left out rather than failing the status call, which gates sign-in:
		// the app then shows initials.
		avatar, err := avatarutil.Stat(avatarutil.StatParams{DataDir: storageutil.GetDataDir(), UserID: status.UserID})
		if err != nil {
			slog.Warn("auth status: profile picture lookup failed", "error", err)
		} else if avatar.Exists {
			body["avatarUpdatedAt"] = avatar.UpdatedAt.UnixMilli()
		}
	}
	return serverutil.Ok().WithData(body)
}

var getAuthStatusRoute = serverutil.ApiRoute("GET", "/auth/status", getAuthStatus)
