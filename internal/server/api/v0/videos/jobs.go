package v0_videos

import (
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/autobutler-org/autobutler/internal/db"
	"github.com/autobutler-org/autobutler/pkg/util/ctxutil"
	"github.com/autobutler-org/autobutler/pkg/util/deputil"
	"github.com/autobutler-org/autobutler/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
	"strconv"
)

// videoJobJSON is the API representation of a video_jobs row.
type videoJobJSON struct {
	ID            int64   `json:"id"`
	JobType       string  `json:"jobType"`
	Status        string  `json:"status"`
	DeviceSerial  string  `json:"deviceSerial,omitempty"`
	InputRelPath  string  `json:"inputRelPath"`
	OutputRelPath string  `json:"outputRelPath,omitempty"`
	Preset        string  `json:"preset,omitempty"`
	Progress      float64 `json:"progress"`
	ErrorMessage  string  `json:"errorMessage,omitempty"`
	CreatedAt     string  `json:"createdAt"`
	UpdatedAt     string  `json:"updatedAt"`
}

func jobToJSON(j db.VideoJob) videoJobJSON {
	return videoJobJSON{
		ID:            j.ID,
		JobType:       j.JobType,
		Status:        j.Status,
		DeviceSerial:  j.DeviceSerial,
		InputRelPath:  j.InputRelPath,
		OutputRelPath: j.OutputRelPath,
		Progress:      j.Progress,
		ErrorMessage:  j.ErrorMessage,
		CreatedAt:     j.CreatedAt.UTC().Format(time.RFC3339),
		UpdatedAt:     j.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

// getVideoJob godoc
// @Summary Get a video job by ID
// @Description Returns current status and progress for a video processing job.
// @Tags videos
// @Produce json
// @Param id path int true "Job ID"
// @Success 200 {object} videoJobJSON
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /videos/jobs/{id} [get]
func getVideoJobHandler(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid job id: %s", idStr))
	}

	job, err := deps.Database().Queries.GetVideoJob(c.Request.Context(), id)
	if errors.Is(err, sql.ErrNoRows) {
		return serverutil.NotFound(fmt.Errorf("job %d not found", id))
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(jobToJSON(job))
}

// listVideoJobsHandler godoc
// @Summary List recent video jobs
// @Description Returns the 50 most recent video processing jobs, newest first.
// @Tags videos
// @Produce json
// @Success 200 {array} videoJobJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /videos/jobs [get]
func listVideoJobsHandler(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	jobs, err := deps.Database().Queries.ListVideoJobs(c.Request.Context())
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result := make([]videoJobJSON, 0, len(jobs))
	for _, j := range jobs {
		result = append(result, jobToJSON(j))
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result)
}

var getVideoJobRoute = serverutil.ApiRoute("GET", "/videos/jobs/:id", getVideoJobHandler)
var listVideoJobsRoute = serverutil.ApiRoute("GET", "/videos/jobs", listVideoJobsHandler)
