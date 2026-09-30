// Package v0_videos serves /api/v0/videos: video metadata, the formats a video can be converted to, and
// converting or trimming one. None of it decodes a frame; it all runs through videoutil's pure-Go sprocket.
package v0_videos

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// Router for /api/v0/videos endpoints.

// NewRouter returns the videos API router.
func NewRouter() serverutil.Router {
	return &router{}
}
