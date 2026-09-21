package v0_auth

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// revokeAllSessions godoc
// @Summary Revoke all sessions (log out everywhere)
// @Description Deletes all active sessions for the authenticated user.
// @Tags auth
// @Produce json
// @Success 200 {object} object{revoked=bool}
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /auth/sessions [delete]
func revokeAllSessions(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok {
		return serverutil.InternalServerError(fmt.Errorf("dependencies not found in context"))
	}

	userID, ok := ctxutil.Get[int64](c, "userID")
	if !ok {
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	}

	if err := authutil.RevokeAllSessions(c.Request.Context(), (*deps).Database().Queries, userID); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(gin.H{"revoked": true})
}

var revokeAllSessionsRoute = serverutil.ApiRoute("DELETE", "/auth/sessions", revokeAllSessions)
