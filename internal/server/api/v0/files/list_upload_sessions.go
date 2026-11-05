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

// listUploadSessions godoc
// @Summary List the caller's resumable uploads
// @Description Returns the caller's upload sessions with what each has committed: those in flight (uploading, or committing while the finished file is flushed and moved into place), oldest first, then those that ended in the last 24 hours (completed, failed, canceled or expired), newest first, at most 50. Only a session's owner sees it, admins included. Sessions live in this instance's memory, so a restart empties the list. This is the source of truth; upload_session_changed events are a hint to refetch and can be dropped.
// @Tags files
// @Produce json
// @Success 200 {object} listUploadSessionsResponse "OK"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /files/upload-sessions [get]
func listUploadSessions(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	store := deps.UploadSessions()
	if store == nil {
		return serverutil.InternalServerError(errors.New("upload sessions are not configured"))
	}

	result := store.ListSessions(uploadutil.ListSessionsParams{UserID: callerID(c)})
	response := listUploadSessionsResponse{
		Active:   make([]uploadSessionSummaryResponse, 0, len(result.Active)),
		Finished: make([]uploadSessionSummaryResponse, 0, len(result.Finished)),
	}
	for _, summary := range result.Active {
		response.Active = append(response.Active, uploadSessionJSON(summary))
	}
	for _, summary := range result.Finished {
		response.Finished = append(response.Finished, uploadSessionJSON(summary))
	}
	return serverutil.Ok().WithData(response)
}

var listUploadSessionsRoute = serverutil.ApiRoute(
	http.MethodGet, "/files/upload-sessions", listUploadSessions,
)
