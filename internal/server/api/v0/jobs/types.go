package v0_jobs

import "github.com/autobutler-org/quark/pkg/util/serverutil"

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listJobsRoute,
		getJobRoute,
		cancelJobRoute,
		retryJobRoute,
	}
}

// retryJobResponse is returned when a retry is queued. JobID is the retried
// job's own id.
type retryJobResponse struct {
	JobID int64 `json:"jobId"`
}
