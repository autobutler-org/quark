package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// getRemoteAccess godoc
// @Summary Get remote access status
// @Description Returns whether remote access is switched on, whether the Tailscale node has actually joined the tailnet, its remote URL once it has, and the last start failure
// @Tags settings
// @Produce json
// @Success 200 {object} RemoteAccessResponse
// @Router /settings/remote-access [get]
func getRemoteAccess(c *gin.Context) *serverutil.Response {
	enabled, _ := settingsutil.GetRemoteAccess()
	return serverutil.Ok().WithData(remoteAccessResponse(enabled))
}

var getRemoteAccessRoute = serverutil.ApiRoute("GET", "/settings/remote-access", getRemoteAccess)
