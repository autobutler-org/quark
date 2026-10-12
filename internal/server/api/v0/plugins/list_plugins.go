package v0_plugins

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

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
