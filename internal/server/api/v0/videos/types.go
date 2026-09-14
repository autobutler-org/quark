package v0_videos

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getMetadataRoute,
		extractFrameRoute,
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
	Format  string `json:"format" example:"mov"`
	Quality string `json:"quality" enums:"original,small"`
}

// transcodeVideoResponse is returned when a transcode is queued.
type transcodeVideoResponse struct {
	JobID int64 `json:"jobId"`
}

// transcodeFormatsResponse lists the formats this device can transcode to.
type transcodeFormatsResponse struct {
	Formats []transcodeFormatJSON `json:"formats"`
}

// transcodeFormatJSON is one format a transcode can write.
type transcodeFormatJSON struct {
	// Format is the value to send as format, the file extension without the dot.
	Format string `json:"format" example:"mov"`
	// Label is its display name.
	Label string `json:"label" example:"MOV"`
}

// extractFrameRequest is the POST body for /videos/extract-frame.
type extractFrameRequest struct {
	RelPath     string `json:"relPath"`
	Serial      string `json:"serial"`
	TimestampMs int64  `json:"timestampMs"`
}

// extractFrameResponse is returned on success.
type extractFrameResponse struct {
	RelPath string `json:"relPath"`
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
}

type albumRefJSON struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}
