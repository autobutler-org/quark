package v0_jobs

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
)

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

// retryRefusalJSON is the body of a 422 refusing a retry whose inputs no
// longer exist or no longer read as a video.
type retryRefusalJSON struct {
	// Error is the cause in full, for logs.
	Error string `json:"error"`
	// Reason is the cause as videoutil.ReasonOf names it, for a transcode
	// whose source is there but can't be read, or empty when there is none to
	// name, such as a source that was deleted.
	Reason videoutil.Reason `json:"reason"`
}
