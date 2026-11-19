// Package v0_albums serves /api/v0/albums: the caller's photo albums, as a list or a nested tree, and the photos in
// them. POST /albums/exports queues a photo-export job copying albums, or the whole library, into a folder,
// and GET /albums/exports/{jobId} summarizes one.
package v0_albums

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
