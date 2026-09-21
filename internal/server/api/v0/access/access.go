// Package v0_access serves /api/v0/access: the path-based grants that share a folder with a user or group —
// listing, setting and revoking them — and what has been shared with the caller.
package v0_access

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
