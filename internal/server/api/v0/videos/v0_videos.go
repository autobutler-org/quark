package v0_videos

import "github.com/autobutler-org/autobutler/pkg/util/serverutil"

// Router for /api/v0/videos endpoints.

type router struct{}

// NewRouter returns the videos API router.
func NewRouter() serverutil.Router {
	return &router{}
}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getVideoMetadataRoute,
		extractVideoFrameRoute,
		trimVideoRoute,
		queueTranscodeRoute,
		getVideoJobRoute,
		listVideoJobsRoute,
	}
}
