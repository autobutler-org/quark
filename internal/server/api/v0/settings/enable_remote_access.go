package v0_settings

import (
	"errors"
	"log"

	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// errRemoteAccessStart is what the client reads when the node fails to start.
// The Go error is a diagnostic: it goes to the log, and GET reports it as the
// status's error field.
var errRemoteAccessStart = errors.New("remote access could not start, the Quark's log has the details")

// enableRemoteAccess godoc
// @Summary Enable remote access via Tailscale
// @Description Starts a Tailscale tsnet node with the provided auth key and proxies traffic to the local server. The node joins the tailnet asynchronously; poll GET for connected. Admin only.
// @Tags settings
// @Accept json
// @Produce json
// @Param body body RemoteAccessRequest true "Tailscale auth key"
// @Success 200 {object} RemoteAccessResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Router /settings/remote-access [post]
func enableRemoteAccess(c *gin.Context) *serverutil.Response {
	if remoteutil.IsRunning() {
		return serverutil.Ok().WithData(remoteAccessResponse(true))
	}
	var req RemoteAccessRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	if req.AuthKey == "" {
		// Until the Quark can fetch its own key (#1815), nothing in the app can
		// supply one — say so rather than blame the request.
		return serverutil.BadRequest(errors.New(
			"remote access needs an auth key, and automatic provisioning is not available yet",
		))
	}
	if err := remoteutil.Start(req.AuthKey); err != nil {
		log.Printf("[remote] failed to start: %v", err)
		return serverutil.InternalServerError(errRemoteAccessStart)
	}
	if err := remoteutil.StartProxy(
		serverutil.ServingPort(),
		serverutil.ServingTLS(),
	); err != nil {
		log.Printf("[remote] failed to start proxy: %v", err)
		remoteutil.Stop()
		return serverutil.InternalServerError(errRemoteAccessStart)
	}
	if err := settingsutil.SetRemoteAccess(true, req.AuthKey); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(remoteAccessResponse(true))
}

var enableRemoteAccessRoute = serverutil.ApiRoute("POST", "/settings/remote-access", enableRemoteAccess)
