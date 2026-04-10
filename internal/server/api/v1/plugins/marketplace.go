package v1_plugins

import (
	"log/slog"
	"strings"

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
	slog.Info("plugins: install requested", "id", id)
	if err := pluginutil.InstallPlugin(id); err != nil {
		slog.Error("plugins: install failed", "id", id, "err", err)
		if strings.Contains(err.Error(), "not found in marketplace") {
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
	slog.Info("plugins: uninstall requested", "id", id)
	if err := pluginutil.UninstallPlugin(id); err != nil {
		slog.Error("plugins: uninstall failed", "id", id, "err", err)
		if isNotInstalledError(err) {
			return serverutil.BadRequest(err)
		}
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

// isNotInstalledError returns true only when the plugin was not found on disk.
func isNotInstalledError(err error) bool {
	return err != nil && strings.Contains(err.Error(), "is not installed")
}

var listMarketplaceRoute = serverutil.ApiRoute("GET", "/plugins/marketplace", listMarketplace)
var installPluginRoute = serverutil.ApiRoute("POST", "/plugins/:id/install", installPlugin)
var uninstallPluginRoute = serverutil.ApiRoute("DELETE", "/plugins/:id", uninstallPlugin)
