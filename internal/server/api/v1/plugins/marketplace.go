package v1_plugins

import (
	"github.com/autobutler-org/autobutler/pkg/util/pluginutil"
	"github.com/autobutler-org/autobutler/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listMarketplace godoc
// @Summary List available plugins in the marketplace
// @Description Returns all plugins available for installation, annotated with installed status
// @Tags plugins
// @Produce json
// @Success 200 {array} pluginutil.MarketplaceEntry
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /plugins/marketplace [get]
func listMarketplace(c *gin.Context) *serverutil.Response {
	entries, err := pluginutil.ListMarketplace()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(entries)
}

// installPlugin godoc
// @Summary Install a plugin
// @Description Installs a plugin from the marketplace by writing its manifest to disk
// @Tags plugins
// @Param id path string true "Plugin ID"
// @Produce json
// @Success 200 {object} serverutil.Response "OK"
// @Failure 400 {object} serverutil.Response "Plugin not found in marketplace"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /plugins/{id}/install [post]
func installPlugin(c *gin.Context) *serverutil.Response {
	id := c.Param("id")
	if err := pluginutil.InstallPlugin(id); err != nil {
		if isNotFoundError(err) {
			return serverutil.BadRequest(err)
		}
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

// uninstallPlugin godoc
// @Summary Uninstall a plugin
// @Description Removes an installed plugin from disk
// @Tags plugins
// @Param id path string true "Plugin ID"
// @Produce json
// @Success 200 {object} serverutil.Response "OK"
// @Failure 400 {object} serverutil.Response "Plugin not installed"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /plugins/{id} [delete]
func uninstallPlugin(c *gin.Context) *serverutil.Response {
	id := c.Param("id")
	if err := pluginutil.UninstallPlugin(id); err != nil {
		if isNotFoundError(err) {
			return serverutil.BadRequest(err)
		}
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

// isNotFoundError checks whether an error is a "not found" kind.
func isNotFoundError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return len(msg) > 0 && (contains(msg, "not found") || contains(msg, "not installed"))
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(s) > 0 && containsAt(s, sub))
}

func containsAt(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

var listMarketplaceRoute = serverutil.ApiRoute("GET", "/plugins/marketplace", listMarketplace)
var installPluginRoute = serverutil.ApiRoute("POST", "/plugins/:id/install", installPlugin)
var uninstallPluginRoute = serverutil.ApiRoute("DELETE", "/plugins/:id", uninstallPlugin)
