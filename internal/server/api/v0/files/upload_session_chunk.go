package v0_files

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"

	"github.com/gin-gonic/gin"
)

// uploadSessionChunk godoc
// @Summary Send one chunk of a resumable upload
// @Description Append the chunk named by Content-Range; the last one commits the file, and the caller owns it if it is new. A session opened by someone else is not found. A 409 carrying X-Upload-Offset is a chunk out of step; one without it is a name already in use. A photo or video's client-rendered thumbnail and preview go to PUT /thumbnails/{filePath} once the last chunk answers with where the file landed.
// @Tags files
// @Accept octet-stream
// @Produce json
// @Param sessionId path string true "Upload session id"
// @Param Content-Range header string true "Byte range of this chunk, e.g. bytes 0-8388607/20971520"
// @Success 200 {object} uploadChunkResponse "OK"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 409 {object} serverutil.Response "Conflict"
// @Security BearerAuth
// @Router /files/upload-session/{sessionId} [put]
func uploadSessionChunk(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	store := deps.UploadSessions()
	if store == nil {
		return serverutil.InternalServerError(errors.New("upload sessions are not configured"))
	}

	chunk, err := uploadutil.ParseContentRange(c.GetHeader("Content-Range"))
	if err != nil {
		return uploadSessionError(c, err)
	}

	result, err := store.WriteChunk(uploadutil.WriteChunkParams{
		Ctx:         c.Request.Context(),
		Destination: uploadDestination(deps),
		SessionID:   c.Param(sessionIDParam),
		UserID:      callerID(c),
		Range:       chunk,
		Body:        c.Request.Body,
	})
	if err != nil {
		return uploadSessionError(c, err)
	}
	// The write check happened when the session was opened; a grant revoked
	// mid-upload does not stop the commit.
	if result.Complete && result.Created {
		access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
		if err != nil {
			slog.Error("access: could not load access to record the owner of an upload", "path", result.Path, "err", err)
		} else {
			grantOwner(c, deps, access, result.Serial, result.Path)
		}
	}
	return serverutil.Ok().WithData(uploadChunkResponse{
		SessionID: result.SessionID,
		Offset:    result.Offset,
		Complete:  result.Complete,
		Path:      result.Path,
	})
}

var uploadSessionChunkRoute = serverutil.ApiRoute(
	http.MethodPut, "/files/upload-session/:"+sessionIDParam, uploadSessionChunk,
)
