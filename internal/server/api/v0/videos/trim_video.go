package v0_videos

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/trimutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// trimVideo godoc
// @Summary Queue a video trim
// @Description Queues a background job that copies the sub-clip [startMs, endMs] of the source video into a new file beside it without re-encoding (fast, lossless). Follow the job with GET /jobs/{id} or the job_* events, and cancel it with DELETE /jobs/{id}; a canceled or failed trim leaves no partial file. The job reports no progress until it completes, because the trimmer has no progress hook yet. A completed job's detail holds relPath, the clip's path, and actualStartMs, where the clip is shown from: startMs, except where there is nothing to hide the lead-in behind or nothing to hide — a start before the video's first keyframe or past its last frame, or a TS output, begins at that keyframe instead. An endMs at or past the end of the video keeps the rest of it; a startMs at or past the end is a 400. The clip keeps the source's format where the device writes it and is an MP4 otherwise. The original file is not modified. A file that can't be read as a video is a 422; an MPEG-TS source fails the job. Needs read access on the video and write access on its folder; the job runs as, and the clip is owned by, the caller.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body trimVideoRequest true "Trim request"
// @Success 202 {object} trimVideoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 422 {object} serverutil.Response "Unprocessable Entity — the file can't be read as a video"
// @Failure 500 {object} serverutil.Response "Internal Server Error — the job could not be queued; the cause is logged"
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

	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if resp := checkEdit(access, req.Serial, req.RelPath); resp != nil {
		return resp
	}

	result, err := trimutil.Enqueue(c.Request.Context(), trimutil.EnqueueParams{
		Queue:    deps.JobQueue(),
		Registry: deps.VFSRegistry(),
		Params: trimutil.Params{
			RelPath: req.RelPath,
			Serial:  req.Serial,
			StartMs: req.StartMs,
			EndMs:   req.EndMs,
		},
		UserID: access.Principal().UserID,
	})
	switch {
	case errors.Is(err, trimutil.ErrInvalidRange), errors.Is(err, trimutil.ErrInvalidPath):
		return serverutil.BadRequest(err)
	case errors.Is(err, videoutil.ErrStartPastEnd):
		return serverutil.BadRequest(fmt.Errorf("startMs (%d) is at or past the end of the video: %w", req.StartMs, err))
	case errors.Is(err, trimutil.ErrSourceNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, videoutil.ErrNotAVideo):
		return unreadableVideo(err)
	case err != nil:
		// Nothing else records why, and the job was never created (#3422).
		slog.Error("trim: could not queue the trim", "path", req.RelPath, "serial", req.Serial, "err", err)
		return serverutil.InternalServerError(fmt.Errorf("couldn't queue the trim: %w", err))
	}

	return serverutil.Accepted().WithContentType(serverutil.ContentTypeJSON).
		WithData(trimVideoResponse{JobID: result.Job.ID})
}

var trimVideoRoute = serverutil.ApiRoute(
	"POST", "/videos/trim", trimVideo,
)
