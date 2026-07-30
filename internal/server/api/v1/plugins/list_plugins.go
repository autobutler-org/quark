package v1_plugins

import (
	"github.com/autobutler-org/autobutler/pkg/util/ctxutil"
	"github.com/autobutler-org/autobutler/pkg/util/deputil"
	"github.com/autobutler-org/autobutler/pkg/util/pluginutil"
	"github.com/autobutler-org/autobutler/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// PluginInfoJSON is the public representation of a running plugin.
type PluginInfoJSON struct {
	ID          string `json:"id"`
	Name        string `json:"name,omitempty"`
	Version     string `json:"version,omitempty"`
	Description string `json:"description,omitempty"`
	Addr        string `json:"addr,omitempty"` // host:port (internal, may be omitted in prod)
}

// listPlugins godoc
// @Summary List installed plugins
// @Description Returns all currently running plugins and their manifests.
// @Tags plugins
// @Produce json
// @Success 200 {object} object{plugins=[]PluginInfoJSON}
// @Security BearerAuth
// @Router /plugins [get]
func listPlugins(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	host := deps.PluginHost()
	if host == nil {
		return serverutil.Ok().WithData(gin.H{"plugins": []PluginInfoJSON{}})
	}

	states := host.Plugins()
	out := make([]PluginInfoJSON, 0, len(states))
	for _, s := range states {
		info := PluginInfoJSON{
			ID:   s.Entry.ID,
			Addr: s.Addr,
		}
		if s.Manifest != nil {
			info.Name = s.Manifest.Name
			info.Version = s.Manifest.Version
			info.Description = s.Manifest.Description
		}
		out = append(out, info)
	}
	return serverutil.Ok().WithData(gin.H{"plugins": out})
}

var listPluginsRoute = serverutil.ApiRoute("GET", "/plugins", listPlugins)

// proxyPlugin godoc
// @Summary Proxy a request to a plugin
// @Description Reverse-proxies the request to the plugin identified by :id.
// @Tags plugins
// @Param id path string true "Plugin ID"
// @Success 200 "Proxied response"
// @Failure 404 {object} serverutil.Response
// @Security BearerAuth
// @Router /plugins/{id}/{path} [any]
func proxyPlugin(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	host := deps.PluginHost()
	if host == nil {
		return serverutil.NotFound(nil)
	}

	pluginID := c.Param("id")
	state, found := host.Plugin(pluginID)
	if !found {
		return serverutil.NotFound(pluginutil.ErrPluginNotFound(pluginID))
	}

	// Strip /plugins/:id prefix before proxying.
	c.Request.URL.Path = "/" + c.Param("path")
	state.Proxy.ServeHTTP(c.Writer, c.Request)
	return nil // proxy wrote the response
}

var proxyPluginRoute = serverutil.NewRoute("ANY", "/plugins/:id/*path", func(c *gin.Context) {
	resp := proxyPlugin(c)
	if resp != nil {
		serverutil.WrapApiRoute(func(c *gin.Context) *serverutil.Response { return resp })(c)
	}
})
