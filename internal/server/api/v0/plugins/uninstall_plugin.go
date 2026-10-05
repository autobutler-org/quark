package v0_plugins

import (
	"errors"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/pluginutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// uninstallPlugin godoc
// @Summary Uninstall a plugin
// @Description Removes an installed plugin from disk
// @Tags plugins
// @Param id path string true "Plugin ID"
// @Produce json
// @Success 200 {object} serverutil.Response "OK"
// @Failure 400 {object} serverutil.Response "Plugin not installed"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /plugins/{id} [delete]
func uninstallPlugin(c *gin.Context) *serverutil.Response {
	id := c.Param("id")
	slog.Info("plugins: uninstall requested", "id", id)
	if err := pluginutil.UninstallPlugin(id); err != nil {
		slog.Error("plugins: uninstall failed", "id", id, "err", err)
		if errors.Is(err, pluginutil.ErrNotInstalled) {
			return serverutil.BadRequest(err)
		}
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

var uninstallPluginRoute = serverutil.ApiRoute("DELETE", "/plugins/:id", uninstallPlugin)
