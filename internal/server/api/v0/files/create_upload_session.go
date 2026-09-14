package v0_files

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"

	"github.com/gin-gonic/gin"
)

// createUploadSession godoc
// @Summary Open a resumable upload session
// @Description Reserve a session for one file; the bytes follow as chunks on PUT. Needs write access on the directory the file lands in. The session belongs to the caller: it is not found for anyone else.
// @Tags files
// @Accept json
// @Produce json
// @Param session body createUploadSessionRequest true "File the session will carry"
// @Success 200 {object} createUploadSessionResponse "OK"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /files/upload-session [post]
func createUploadSession(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	store := deps.UploadSessions()
	if store == nil {
		return serverutil.InternalServerError(errors.New("upload sessions are not configured"))
	}

	var request createUploadSessionRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		return serverutil.BadRequest(err)
	}
	access, err := loadAccess(c, deps)
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	check := access.Check(request.Serial, request.RootDir, accessutil.Write)
	if !check.Readable {
		return serverutil.NotFound(errNoAccess)
	}
	if !check.Allowed {
		return serverutil.Forbidden(errReadOnly)
	}

	result, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: uploadDestination(deps),
		RootDir:     request.RootDir,
		FileName:    request.FileName,
		TotalSize:   request.TotalSize,
		Serial:      request.Serial,
		Overwrite:   request.Overwrite,
		UserID:      access.Principal().UserID,
	})
	if err != nil {
		return uploadSessionError(c, err)
	}
	return serverutil.Ok().WithData(createUploadSessionResponse{
		SessionID: result.SessionID,
		Offset:    result.Offset,
		ExpiresAt: result.ExpiresAt.UTC(),
	})
}

// The session endpoints sit at /files/upload-session, not the more obvious
// /files/upload/session. POST /files//upload/*rootDir looks like it reserves a
// different subtree, but gin runs the group prefix and the route path through
// path.Join, which collapses that deliberate double slash — so the route
// actually registered is /api/v0/files/upload/*rootDir, and any static child
// under /files/upload/ panics at startup with a wildcard conflict. Verified by
// TestUploadSessionRoutesRegisterWithoutConflict.
var createUploadSessionRoute = serverutil.ApiRoute(
	http.MethodPost, "/files/upload-session", createUploadSession,
)
