package v0_videos

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// trimVideo godoc
// @Summary Trim a video clip
// @Description Copies the sub-clip [startMs, endMs] of the source video into a new file beside it without re-encoding (fast, lossless). The clip is shown from startMs: the frames back to the keyframe before it are kept but hidden, so they still decode. actualStartMs reports where the clip is shown from, which is startMs except where there is nothing to hide the lead-in behind or nothing to hide: a start before the video's first keyframe or past its last frame, or a TS output, begins at that keyframe instead. An endMs at or past the end of the video keeps the rest of it; a startMs at or past the end is a 400. The clip keeps the source's format where the device writes it and is an MP4 otherwise. The original file is not modified. An MPEG-TS source cannot be trimmed and is a 422. Needs read access on the video and write access on its folder; the caller owns the new clip.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body trimVideoRequest true "Trim request"
// @Success 200 {object} trimVideoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 422 {object} serverutil.Response "Unprocessable Entity — the video's container can't be trimmed"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /videos/trim [post]
func trimVideo(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req trimVideoRequest
	if err := json.NewDecoder(c.Request.Body).Decode(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	if req.RelPath == "" {
		return serverutil.BadRequest(fmt.Errorf("relPath is required"))
	}
	if req.StartMs < 0 {
		return serverutil.BadRequest(fmt.Errorf("startMs must be >= 0"))
	}
	if req.EndMs <= req.StartMs {
		return serverutil.BadRequest(fmt.Errorf("endMs must be greater than startMs"))
	}

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if resp := checkEdit(access, req.Serial, req.RelPath); resp != nil {
		return resp
	}

	fsys := filesVFS(deps, req.Serial)
	if fsys == nil {
		return serverutil.NotFound(fmt.Errorf("video not found: %s", req.RelPath))
	}
	if isRoot(req.RelPath) {
		return serverutil.BadRequest(errInvalidPath)
	}

	// Stream copy is fast (header rewrite only); 5 minutes is generous headroom.
	trimCtx, trimCancel := context.WithTimeout(c.Request.Context(), 5*time.Minute)
	defer trimCancel()

	result, err := videoutil.TrimFile(trimCtx, videoutil.TrimFileParams{
		FS:    fsys,
		Path:  req.RelPath,
		Start: time.Duration(req.StartMs) * time.Millisecond,
		End:   time.Duration(req.EndMs) * time.Millisecond,
	})
	switch {
	case errors.Is(err, videoutil.ErrStartPastEnd):
		return serverutil.BadRequest(fmt.Errorf("startMs (%d) is at or past the end of the video: %w", req.StartMs, err))
	case errors.Is(err, videoutil.ErrCannotTrim):
		return serverutil.NewResponse().WithStatusCode(http.StatusUnprocessableEntity).WithError(err)
	case err != nil:
		return openError(err, req.RelPath)
	}
	// TrimFile wrote the clip under a name nothing had, so it is always a new
	// file and never takes ownership of one that was already there.
	grantOwner(c, deps, access, req.Serial, result.Path)
	// The event a conversion publishes for its output, so open file browsers
	// list the clip now rather than at their next refresh.
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: result.Path, DeviceSerial: req.Serial})
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).
		WithData(trimVideoResponse{RelPath: result.Path, ActualStartMs: result.Start.Milliseconds()})
}

var trimVideoRoute = serverutil.ApiRoute(
	"POST", "/videos/trim", trimVideo,
)
