package v0_videos

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/transcodeutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

// transcodeVideo godoc
// @Summary Queue a video transcode
// @Description Queues a background job that converts the source video into a new file beside it, in any format GET /videos/transcode/formats lists. Original quality keeps the source resolution, and copies the streams without re-encoding when the format's container accepts them; small caps the height at 480 lines. Converting to the source's own format needs small quality. The output is never upscaled and never overwrites a file. Follow the job with GET /jobs/{id} or the job_* events; an upload event announces the output file. Needs read access on the video and write access on its folder; the job runs as, and its output is owned by, the caller.
// @Tags videos
// @Accept json
// @Produce json
// @Param body body transcodeVideoRequest true "Transcode request"
// @Success 202 {object} transcodeVideoResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 501 {object} serverutil.Response "Not Implemented — ffmpeg not available"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /videos/transcode [post]
func transcodeVideo(c *gin.Context) *serverutil.Response {
	if !videoutil.Available() {
		return serverutil.NewResponse().
			WithStatusCode(http.StatusNotImplemented).
			WithContentType(serverutil.ContentTypeJSON).
			WithData(gin.H{"error": "ffmpeg is not installed on this device"})
	}

	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req transcodeVideoRequest
	if err := json.NewDecoder(c.Request.Body).Decode(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}

	// Access comes before validation, so a caller who can't read the video
	// can't tell a missing file from a bad request.
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if resp := checkEdit(access, req.Serial, req.RelPath); resp != nil {
		return resp
	}

	result, err := transcodeutil.Enqueue(c.Request.Context(), transcodeutil.EnqueueParams{
		Queue:   deps.JobQueue(),
		Storage: deps.StorageService(),
		Params: transcodeutil.Params{
			RelPath: req.RelPath,
			Serial:  req.Serial,
			Format:  videoutil.Format(req.Format),
			Quality: videoutil.Quality(req.Quality),
		},
		UserID: access.Principal().UserID,
	})
	switch {
	case errors.Is(err, transcodeutil.ErrInvalidFormat), errors.Is(err, transcodeutil.ErrInvalidQuality),
		errors.Is(err, transcodeutil.ErrInvalidPath):
		return serverutil.BadRequest(err)
	case errors.Is(err, transcodeutil.ErrSourceNotFound):
		return serverutil.NotFound(err)
	case err != nil:
		return serverutil.InternalServerError(fmt.Errorf("queue transcode: %w", err))
	}

	return serverutil.Accepted().WithContentType(serverutil.ContentTypeJSON).
		WithData(transcodeVideoResponse{JobID: result.Job.ID})
}

var transcodeVideoRoute = serverutil.ApiRoute(
	"POST", "/videos/transcode", transcodeVideo,
)
