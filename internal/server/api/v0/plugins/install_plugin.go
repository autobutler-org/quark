package v0_plugins

import (
	"errors"
	"log/slog"

	"github.com/autobutler-org/quark/pkg/util/pluginutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// installPlugin godoc
// @Summary Install a plugin
// @Description Installs a plugin from the marketplace by writing its manifest to disk
// @Tags plugins
// @Param id path string true "Plugin ID"
// @Produce json
// @Success 200 {object} serverutil.Response "OK"
// @Failure 400 {object} serverutil.Response "Plugin not found in marketplace"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /plugins/{id}/install [post]
func installPlugin(c *gin.Context) *serverutil.Response {
	id := c.Param("id")
	slog.Info("plugins: install requested", "id", id)
	if err := pluginutil.InstallPlugin(id); err != nil {
		slog.Error("plugins: install failed", "id", id, "err", err)
		if errors.Is(err, pluginutil.ErrNotInCatalog) {
			return serverutil.BadRequest(err)
		}
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

var installPluginRoute = serverutil.ApiRoute("POST", "/plugins/:id/install", installPlugin)
