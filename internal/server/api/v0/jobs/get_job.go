package v0_jobs

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getJob godoc
// @Summary Get a background job
// @Description Returns one background job by id. A caller who is not an admin gets only a job they queued whose file they can still read, with error left blank; any other job is 404.
// @Tags jobs
// @Produce json
// @Param id path int true "Job ID"
// @Success 200 {object} jobutil.Job
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /jobs/{id} [get]
func getJob(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	access, job, resp := loadJob(c, deps)
	if resp != nil {
		return resp
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(access.RedactJob(job))
}

var getJobRoute = serverutil.ApiRoute(
	"GET", "/jobs/:id", getJob,
)
