// Package v0_plugins serves /api/v0/plugins: the installed plugins, the marketplace of plugins that can be
// installed, and installing and uninstalling one.
package v0_plugins

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
