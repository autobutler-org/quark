// Package v0_jobs serves /api/v0/jobs: listing background jobs, and getting, canceling or retrying one.
package v0_jobs

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the router for /api/v0/jobs, the background job queue.
func NewRouter() serverutil.Router {
	return &router{}
}
