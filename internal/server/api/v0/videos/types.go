package v0_videos

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getMetadataRoute,
		trimVideoRoute,
		transcodeVideoRoute,
		listTranscodeFormatsRoute,
	}
}

// transcodeVideoRequest is the POST body for /videos/transcode.
type transcodeVideoRequest struct {
	RelPath string `json:"relPath"`
	Serial  string `json:"serial"`
	// Format is one of the formats GET /videos/transcode/formats lists.
	Format string `json:"format" example:"mkv"`
	// Quality is optional. A conversion copies the streams, so original is
	// the only quality; small, which needed a re-encode, is refused.
	Quality string `json:"quality,omitempty" enums:"original"`
}

// transcodeVideoResponse is returned when a transcode is queued.
type transcodeVideoResponse struct {
	JobID int64 `json:"jobId"`
}

// transcodeFormatsResponse lists the formats a video can be converted to.
type transcodeFormatsResponse struct {
	Formats []transcodeFormatJSON `json:"formats"`
}

// transcodeFormatJSON is one format a transcode can write.
type transcodeFormatJSON struct {
	// Format is the value to send as format, the file extension without the dot.
	Format string `json:"format" example:"mkv"`
	// Label is its display name.
	Label string `json:"label" example:"MKV"`
}

// trimVideoRequest is the POST body for /videos/trim.
type trimVideoRequest struct {
	RelPath string `json:"relPath"`
	Serial  string `json:"serial"`
	StartMs int64  `json:"startMs"`
	EndMs   int64  `json:"endMs"`
}

// trimVideoResponse is returned on success.
type trimVideoResponse struct {
	RelPath string `json:"relPath"`
	// ActualStartMs is where the clip really begins in the source: startMs
	// snapped back to the keyframe at or before it.
	ActualStartMs int64 `json:"actualStartMs"`
}

type albumRefJSON struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}
