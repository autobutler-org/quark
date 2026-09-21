package v0_jobs

import (
	"errors"
	"net/http"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// errCreatorReadOnly refuses a retry whose job could not write its output,
// because the account that queued it can no longer write the folder.
var errCreatorReadOnly = errors.New("the account that queued this job can't save files in that folder")

// retryJob godoc
// @Summary Retry a background job
// @Description Resets a failed job to pending so it runs again. It keeps its id and createdAt; progress, error, startedAt, and finishedAt are cleared, and the returned jobId is the same id. Only the account that queued the job, or an admin, may retry it; any other caller gets 404. The job runs as the account that queued it, which must still be active and able to write the folder of the file the job works on, or the retry is refused with 403. A retry whose inputs no longer exist, such as a transcode of a video that was moved or deleted, is refused with 422.
// @Tags jobs
// @Produce json
// @Param id path int true "Job ID"
// @Success 202 {object} retryJobResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden — the account that queued the job can no longer sign in or write the folder"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 409 {object} serverutil.Response "Conflict — only a failed job can be retried, and a job already reset by a retry is no longer failed"
// @Failure 422 {object} serverutil.Response "Unprocessable Entity — the job's inputs no longer exist"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /jobs/{id}/retry [post]
func retryJob(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	_, job, resp := loadJob(c, deps)
	if resp != nil {
		return resp
	}
	creator, err := accessutil.LoadCreator(accessutil.LoadCreatorParams{
		Ctx:      c.Request.Context(),
		Database: deps.Database(),
		Storage:  deps.StorageService(),
		UserID:   job.UserID,
	})
	switch {
	case errors.Is(err, accessutil.ErrCreatorInactive):
		return serverutil.Forbidden(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	if serial, relPath := job.Source(); relPath != "" &&
		!creator.Access.Check(serial, path.Dir(accessutil.Canonical(relPath)), accessutil.Write).Allowed {
		return serverutil.Forbidden(errCreatorReadOnly)
	}

	result, err := deps.JobQueue().Retry(c.Request.Context(), jobutil.RetryParams{ID: job.ID})
	switch {
	case errors.Is(err, jobutil.ErrJobNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, jobutil.ErrJobNotRetryable):
		return serverutil.Conflict(err)
	case errors.Is(err, jobutil.ErrRetryRejected):
		return serverutil.NewResponse().WithStatusCode(http.StatusUnprocessableEntity).WithError(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	return serverutil.Accepted().WithContentType(serverutil.ContentTypeJSON).
		WithData(retryJobResponse{JobID: result.Job.ID})
}

var retryJobRoute = serverutil.ApiRoute(
	"POST", "/jobs/:id/retry", retryJob,
)
