package v0_plugins

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/pluginutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// proxyPlugin godoc
// @Summary Proxy a request to a plugin
// @Description Reverse-proxies the request to the plugin identified by :id.
// @Tags plugins
// @Param id path string true "Plugin ID"
// @Param path path string true "Path on the plugin's own server"
// @Success 200 "Proxied response"
// @Failure 404 {object} serverutil.Response
// @Security BearerAuth
// @Router /plugins/{id}/{path} [get]
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

var proxyPluginRoute = serverutil.ApiRoute("GET", "/plugins/:id/*path", proxyPlugin)
