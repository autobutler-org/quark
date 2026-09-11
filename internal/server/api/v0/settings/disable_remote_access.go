package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// disableRemoteAccess godoc
// @Summary Disable remote access
// @Description Logs the Tailscale tsnet node out, stops it, and deletes its state, so re-enabling needs a fresh auth key. Admin only.
// @Tags settings
// @Produce json
// @Success 200 {object} RemoteAccessResponse
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /settings/remote-access [delete]
func disableRemoteAccess(c *gin.Context) *serverutil.Response {
	if err := remoteutil.Disable(); err != nil {
		return serverutil.InternalServerError(err)
	}
	if err := settingsutil.SetRemoteAccess(false, ""); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(RemoteAccessResponse{
		Enabled: false,
	})
}

var disableRemoteAccessRoute = serverutil.ApiRoute("DELETE", "/settings/remote-access", disableRemoteAccess)
