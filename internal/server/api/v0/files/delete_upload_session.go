package v0_files

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"

	"github.com/gin-gonic/gin"
)

// deleteUploadSession godoc
// @Summary Abandon a resumable upload session
// @Description Drops the session and the bytes staged for it
// @Tags files
// @Produce json
// @Param sessionId path string true "Upload session id"
// @Success 200 {object} serverutil.Response "OK"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Security BearerAuth
// @Router /files/upload-session/{sessionId} [delete]
func deleteUploadSession(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	store := deps.UploadSessions()
	if store == nil {
		return serverutil.InternalServerError(errors.New("upload sessions are not configured"))
	}

	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{
		SessionID: c.Param(sessionIDParam),
		UserID:    callerID(c),
	}); err != nil {
		return uploadSessionError(c, err)
	}
	return serverutil.Ok()
}

var deleteUploadSessionRoute = serverutil.ApiRoute(
	http.MethodDelete, "/files/upload-session/:"+sessionIDParam, deleteUploadSession,
)
