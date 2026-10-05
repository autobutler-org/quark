package v0_plugins

import "github.com/autobutler-org/quark/pkg/util/serverutil"

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listPluginsRoute,
		listMarketplaceRoute,
		installPluginRoute,
		uninstallPluginRoute,
	}
}
