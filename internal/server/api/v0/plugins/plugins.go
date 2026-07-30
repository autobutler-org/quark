// Package v0_plugins serves /api/v0/plugins: the list of running plugins, and
// a reverse proxy to each plugin's own HTTP server.
package v0_plugins

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
