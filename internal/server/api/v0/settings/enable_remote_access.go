package v0_settings

import (
	"errors"
	"io"
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
// @Description Starts a Tailscale tsnet node and proxies traffic to the local server. Every enable presents a fresh pre-auth key from the provisioning service, which authKey overrides. The node keeps its machine key across disable, so it rejoins the tailnet as the same node with the same IP. The node joins the tailnet asynchronously; poll GET for connected. Admin only.
// @Tags settings
// @Accept json
// @Produce json
// @Param body body RemoteAccessRequest false "Optional pre-auth key override"
// @Success 200 {object} RemoteAccessResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/remote-access [post]
func enableRemoteAccess(c *gin.Context) *serverutil.Response {
	var req RemoteAccessRequest
	if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
		return serverutil.BadRequest(err)
	}
	provision := provisionAuthKey
	if req.AuthKey != "" {
		provision = func() (string, error) { return req.AuthKey, nil }
	}
	if err := remoteutil.Enable(
		serverutil.ServingPort(),
		serverutil.ServingTLS(),
		provision,
	); err != nil {
		log.Printf("[remote] failed to enable: %v", err)
		return serverutil.InternalServerError(errRemoteAccessStart)
	}
	if err := settingsutil.SetRemoteAccess(true); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(remoteAccessResponse(true))
}

var enableRemoteAccessRoute = serverutil.ApiRoute("POST", "/settings/remote-access", enableRemoteAccess)
