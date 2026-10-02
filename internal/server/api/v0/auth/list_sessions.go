package v0_auth

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listSessions godoc
// @Summary List active sessions
// @Description Returns all non-expired sessions for the authenticated user. Each session is identified by the SHA-256 hash of its token — pass this ID to DELETE /auth/sessions/{id} to revoke a specific session. The session the request was authenticated with has current=true.
// @Tags auth
// @Produce json
// @Success 200 {object} object{sessions=[]authutil.SessionInfo}
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /auth/sessions [get]
func listSessions(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok {
		return serverutil.InternalServerError(fmt.Errorf("dependencies not found in context"))
	}

	userID, ok := ctxutil.Get[int64](c, "userID")
	if !ok {
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	}

	// Absent under HTTP Basic auth, which has no session: nothing is current.
	sessionID, _ := ctxutil.Get[string](c, "sessionID")

	sessions, err := authutil.ListActiveSessions(c.Request.Context(), (*deps).Database().Queries, userID, sessionID)
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if sessions == nil {
		sessions = []authutil.SessionInfo{}
	}
	return serverutil.Ok().WithData(gin.H{"sessions": sessions})
}

var listSessionsRoute = serverutil.ApiRoute("GET", "/auth/sessions", listSessions)
