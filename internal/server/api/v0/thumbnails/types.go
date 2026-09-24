package v0_thumbnails

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

// putThumbnailResponse lists the derivatives a PUT stored.
type putThumbnailResponse struct {
	// Stored names each kind stored: "thumbnail", "preview".
	Stored []string `json:"stored"`
}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getThumbnailRoute,
		putThumbnailRoute,
	}
}
