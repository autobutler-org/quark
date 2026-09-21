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

// getUploadSession godoc
// @Summary Ask what a resumable upload has committed
// @Description Returns the committed offset a resuming client continues from
// @Tags files
// @Produce json
// @Param sessionId path string true "Upload session id"
// @Success 200 {object} uploadSessionStatusResponse "OK"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Security BearerAuth
// @Router /files/upload-session/{sessionId} [get]
func getUploadSession(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	store := deps.UploadSessions()
	if store == nil {
		return serverutil.InternalServerError(errors.New("upload sessions are not configured"))
	}

	result, err := store.DescribeSession(uploadutil.DescribeSessionParams{
		SessionID: c.Param(sessionIDParam),
		UserID:    callerID(c),
	})
	if err != nil {
		return uploadSessionError(c, err)
	}
	return serverutil.Ok().WithData(uploadSessionStatusResponse{
		SessionID: result.SessionID,
		Offset:    result.Offset,
		TotalSize: result.TotalSize,
		FileName:  result.FileName,
		RootDir:   result.RootDir,
		ExpiresAt: result.ExpiresAt.UTC(),
	})
}

var getUploadSessionRoute = serverutil.ApiRoute(
	http.MethodGet, "/files/upload-session/:"+sessionIDParam, getUploadSession,
)
