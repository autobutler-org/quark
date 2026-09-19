package v0_jobs

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// cancelJob godoc
// @Summary Cancel a background job
// @Description Cancels a pending or running job and returns it, now canceled. A pending job never runs; a running job is stopped and cleans up after itself. Only the account that queued the job, or an admin, may cancel it; any other caller gets 404.
// @Tags jobs
// @Produce json
// @Param id path int true "Job ID"
// @Success 200 {object} jobutil.Job
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 409 {object} serverutil.Response "Conflict — the job has already finished"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /jobs/{id} [delete]
func cancelJob(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, job, resp := loadJob(c, deps)
	if resp != nil {
		return resp
	}
	result, err := deps.JobQueue().Cancel(c.Request.Context(), jobutil.CancelParams{ID: job.ID})
	switch {
	case errors.Is(err, jobutil.ErrJobNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, jobutil.ErrJobFinished):
		return serverutil.Conflict(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(access.RedactJob(result.Job))
}

var cancelJobRoute = serverutil.ApiRoute(
	"DELETE", "/jobs/:id", cancelJob,
)
