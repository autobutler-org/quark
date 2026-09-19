package v0_jobs

import (
	"errors"
	"fmt"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// parseJobID reads the :id path parameter.
func parseJobID(c *gin.Context) (int64, error) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid job id %q", c.Param("id"))
	}
	return id, nil
}

// loadJob loads the caller's access and the job the :id path parameter names.
// A job the caller may not see answers 404, the same as one that doesn't
// exist, so ids can't be probed (#1979).
func loadJob(c *gin.Context, deps deputil.Dependencies) (accessutil.Access, jobutil.Job, *serverutil.Response) {
	id, err := parseJobID(c)
	if err != nil {
		return accessutil.Access{}, jobutil.Job{}, serverutil.BadRequest(err)
	}
	access, err := accessutil.LoadRequest(c, deps.Database(), deps.StorageService())
	if err != nil {
		return accessutil.Access{}, jobutil.Job{}, serverutil.InternalServerError(err)
	}
	result, err := deps.JobQueue().Get(c.Request.Context(), jobutil.GetParams{ID: id})
	switch {
	case errors.Is(err, jobutil.ErrJobNotFound):
		return accessutil.Access{}, jobutil.Job{}, serverutil.NotFound(err)
	case err != nil:
		return accessutil.Access{}, jobutil.Job{}, serverutil.InternalServerError(err)
	case !access.CanSeeJob(result.Job):
		return accessutil.Access{}, jobutil.Job{}, serverutil.NotFound(jobutil.ErrJobNotFound)
	}
	return access, result.Job, nil
}
