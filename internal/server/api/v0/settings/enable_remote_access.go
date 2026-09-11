package v0_settings

import (
	"errors"
	"io"
	"log"

	"github.com/autobutler-org/quark/pkg/util/provisionutil"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/gin-gonic/gin"
)

// errRemoteAccessStart is what the client reads when the node fails to start.
// The Go error is a diagnostic: it goes to the log, and GET reports it as the
// status's error field.
var errRemoteAccessStart = errors.New("remote access could not start, the Quark's log has the details")

// errRemoteAccessUnavailable is what the client reads when this build cannot
// ask for a key at all.
var errRemoteAccessUnavailable = errors.New("remote access is not available in this build of Quark")

// enableRemoteAccess godoc
// @Summary Enable remote access via Tailscale
// @Description Starts a Tailscale tsnet node and proxies traffic to the local server. A Quark with no tailnet enrollment fetches a pre-auth key from the provisioning service; authKey overrides that key. The node joins the tailnet asynchronously; poll GET for connected. Admin only.
// @Tags settings
// @Accept json
// @Produce json
// @Param body body RemoteAccessRequest false "Optional pre-auth key override"
// @Success 200 {object} RemoteAccessResponse
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 403 {object} serverutil.Response "Forbidden"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "This build has no provisioning secret"
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
	if err := remoteutil.EnsureStarted(
		serverutil.ServingPort(),
		serverutil.ServingTLS(),
		provision,
	); err != nil {
		log.Printf("[remote] failed to enable: %v", err)
		if errors.Is(err, provisionutil.ErrNoSecret) {
			return serverutil.ServiceUnavailable(errRemoteAccessUnavailable)
		}
		return serverutil.InternalServerError(errRemoteAccessStart)
	}
	if err := settingsutil.SetRemoteAccess(true); err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(remoteAccessResponse(true))
}

var enableRemoteAccessRoute = serverutil.ApiRoute("POST", "/settings/remote-access", enableRemoteAccess)
