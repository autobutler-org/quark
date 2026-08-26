package v0_plugins

import (
	"github.com/autobutler-org/quark/pkg/util/pluginutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listPlugins godoc
// @Summary List installed plugins
// @Description Returns all installed plugins from the plugins directory
// @Tags plugins
// @Produce json
// @Success 200 {array} pluginutil.Manifest
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /plugins [get]
func listPlugins(_ *gin.Context) *serverutil.Response {
	plugins, err := pluginutil.ListPlugins()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(plugins)
}

var listPluginsRoute = serverutil.ApiRoute("GET", "/plugins", listPlugins)
