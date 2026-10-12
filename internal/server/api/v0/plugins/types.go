package v0_plugins

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// PluginInfoJSON is the public representation of a running plugin.
type PluginInfoJSON struct {
	ID          string `json:"id"`
	Name        string `json:"name,omitempty"`
	Version     string `json:"version,omitempty"`
	Description string `json:"description,omitempty"`
	Addr        string `json:"addr,omitempty"` // host:port (internal, may be omitted in prod)
}

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listPluginsRoute,
		proxyPluginRoute,
	}
}
