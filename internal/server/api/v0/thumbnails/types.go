package v0_thumbnails

import (
	"time"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

// clientRenderResponse is the 404 body for a video or HEIC the device could
// not render a thumbnail for (#2379).
type clientRenderResponse struct {
	Error string `json:"error"`
	// ClientRender tells a client that may write the file to render its
	// thumbnail (JPEG, long edge 400) and PUT it to /thumbnails/{filePath}.
	ClientRender bool `json:"clientRender"`
	// ModTime is the file's modification time, so a client can remember a
	// render that failed for this version of the file and not retry it.
	ModTime time.Time `json:"modTime"`
}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getThumbnailRoute,
		putThumbnailRoute,
	}
}
