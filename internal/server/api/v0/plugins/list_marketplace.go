package v0_plugins

import (
	"github.com/autobutler-org/quark/pkg/util/pluginutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listMarketplace godoc
// @Summary List available plugins in the marketplace
// @Description Returns all plugins available for installation, annotated with installed status
// @Tags plugins
// @Produce json
// @Success 200 {array} pluginutil.MarketplaceEntry
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /plugins/marketplace [get]
func listMarketplace(_ *gin.Context) *serverutil.Response {
	entries, err := pluginutil.ListMarketplace()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(entries)
}

var listMarketplaceRoute = serverutil.ApiRoute("GET", "/plugins/marketplace", listMarketplace)
