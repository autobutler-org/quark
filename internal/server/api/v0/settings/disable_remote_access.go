package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// disableRemoteAccess godoc
// @Summary Disable remote access
// @Description Logs the Tailscale tsnet node out and stops it. Its state, with the machine key, is kept, so re-enabling rejoins as the same node with the same IP. Admin only.
// @Tags settings
// @Produce json
// @Success 200 {object} RemoteAccessResponse
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/remote-access [delete]
func disableRemoteAccess(c *gin.Context) *serverutil.Response {
	if err := remoteutil.Disable(); err != nil {
		return serverutil.InternalServerError(err)
	}
	if err := settingsutil.SetRemoteAccess(false); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(RemoteAccessResponse{
		Enabled: false,
	})
}

var disableRemoteAccessRoute = serverutil.ApiRoute("DELETE", "/settings/remote-access", disableRemoteAccess)
