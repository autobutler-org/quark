// Package v0_videos serves /api/v0/videos: video metadata, the transcode formats on offer, and transcoding,
// trimming or extracting a frame.
package v0_videos

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// Router for /api/v0/videos endpoints.

// NewRouter returns the videos API router.
func NewRouter() serverutil.Router {
	return &router{}
}
