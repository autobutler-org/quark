// Package v0_favorites serves the photo favorites, which sit under /api/v0/photos (/photos/favorite and
// /photos/favorites): marking a photo as a favorite, checking whether one is, and listing them.
package v0_favorites

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
