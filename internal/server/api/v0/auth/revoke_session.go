package v0_auth

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// revokeSession godoc
// @Summary Revoke a session by ID
// @Description Deletes a specific session. The session ID is the SHA-256 hex hash of the session token, as returned by GET /auth/sessions.
// @Tags auth
// @Produce json
// @Param id path string true "Session ID (hex SHA-256 of token)"
// @Success 200 {object} object{revoked=bool}
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /auth/sessions/{id} [delete]
func revokeSession(c *gin.Context) *serverutil.Response {
	deps, ok := getQueries(c)
	if !ok {
		return serverutil.InternalServerError(fmt.Errorf("dependencies not found in context"))
	}

	userID, ok := ctxutil.Get[int64](c, "userID")
	if !ok {
		return serverutil.Unauthorized(fmt.Errorf("not authenticated"))
	}

	sessionID := c.Param("id")
	if sessionID == "" {
		return serverutil.BadRequest(fmt.Errorf("session id is required"))
	}

	deleted, err := authutil.RevokeSession(c.Request.Context(), (*deps).Database().Queries, userID, sessionID)
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if !deleted {
		return serverutil.NotFound(fmt.Errorf("session not found"))
	}
	return serverutil.Ok().WithData(gin.H{"revoked": true})
}

var revokeSessionRoute = serverutil.ApiRoute("DELETE", "/auth/sessions/:id", revokeSession)
