// Package v0_photos serves /api/v0/photos: the photo library listing and its file name search, a photo's
// metadata, likely duplicates, where photos were taken (GET /photos/locations) and the offline map tiles their
// map is drawn on (GET /photos/map-tiles/{z}/{x}/{y}), and rotating or copying a photo. The library index status
// and pausing or resuming the pass behind it, GET /photos/index-status and POST /photos/index/pause and
// /photos/index/resume, are admin-only.
package v0_photos

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}

// NewAdminRouter returns the photo library index routes. Mount it behind
// middleware.RequireAdmin: the status names failed files on every device, and
// a pause holds the pass for everyone.
func NewAdminRouter() serverutil.Router {
	return &adminRouter{}
}
