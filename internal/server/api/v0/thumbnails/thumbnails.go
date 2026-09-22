// Package v0_thumbnails serves /api/v0/thumbnails, the cached image previews the photo and file views load.
package v0_thumbnails

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
