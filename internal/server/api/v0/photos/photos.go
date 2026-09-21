// Package v0_photos serves /api/v0/photos: the photo library listing, a photo's metadata, likely duplicates, and
// rotating or copying a photo.
package v0_photos

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// Router for /api/v0/photos endpoints
// Registers the /photos route

func NewRouter() serverutil.Router {
	return &router{}
}
