package v0_jobs

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listJobs godoc
// @Summary List background jobs
// @Description Returns every job of the requested kinds, newest first, finished ones included. This is the source of truth for job state; the job_* events are a hint to refresh and can be dropped.
// @Tags jobs
// @Produce json
// @Param kind query []string true "Job kinds to list; repeat for more than one (kind=video-transcode&kind=...)" collectionFormat(multi)
// @Success 200 {array} jobutil.Job
// @Failure 400 {object} serverutil.Response "Bad Request — kind is missing, empty, or not a registered kind"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /jobs [get]
func listJobs(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	result, err := deps.JobQueue().List(c.Request.Context(), jobutil.ListParams{Kinds: c.QueryArray("kind")})
	switch {
	case errors.Is(err, jobutil.ErrKindRequired), errors.Is(err, jobutil.ErrUnknownKind):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result.Jobs)
}

var listJobsRoute = serverutil.ApiRoute(
	"GET", "/jobs", listJobs,
)
