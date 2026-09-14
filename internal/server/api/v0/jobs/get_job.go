package v0_jobs

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getJob godoc
// @Summary Get a background job
// @Description Returns one background job by id.
// @Tags jobs
// @Produce json
// @Param id path int true "Job ID"
// @Success 200 {object} jobutil.Job
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /jobs/{id} [get]
func getJob(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	id, err := parseJobID(c)
	if err != nil {
		return serverutil.BadRequest(err)
	}
	result, err := deps.JobQueue().Get(c.Request.Context(), jobutil.GetParams{ID: id})
	switch {
	case errors.Is(err, jobutil.ErrJobNotFound):
		return serverutil.NotFound(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result.Job)
}

var getJobRoute = serverutil.ApiRoute(
	"GET", "/jobs/:id", getJob,
)
