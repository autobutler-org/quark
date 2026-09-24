package v0_settings

import (
	"errors"
	"log"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// errPairDevice is what the client reads when the provisioning service could
// not mint a key. The Go error goes to the log.
var errPairDevice = errors.New("the Quark could not get a key for this device, the Quark's log has the details")

// pairDevice godoc
// @Summary Pair a device for remote access
// @Description Mints a single-use pre-auth key that adds the caller's device, such as a phone, to this Quark's Headscale household, and returns what the device needs to join the tailnet and reach the Quark. Any signed-in user may call it. 409 when the Quark is on the user's own tailnet, when remote access is off, or when the Quark has no household to add to; 503 while remote access is still connecting.
// @Tags settings
// @Produce json
// @Success 200 {object} PairDeviceResponse
// @Failure 401 {object} serverutil.Response "Unauthorized"
// @Failure 409 {object} serverutil.Response "Custom tailnet, remote access off, or no household"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "Remote access is still connecting"
// @Security BearerAuth
// @Router /settings/remote-access/devices [post]
func pairDevice(c *gin.Context) *serverutil.Response {
	if username, ok := ctxutil.Get[string](c, "username"); !ok || username == "" {
		return serverutil.Unauthorized(errors.New("authentication required"))
	}
	result, err := remoteutil.PairDevice()
	switch {
	case errors.Is(err, remoteutil.ErrCustomTailnet),
		errors.Is(err, remoteutil.ErrRemoteAccessOff),
		errors.Is(err, remoteutil.ErrNoHousehold):
		return serverutil.Conflict(err)
	case errors.Is(err, remoteutil.ErrNotConnected):
		return serverutil.ServiceUnavailable(err)
	case err != nil:
		log.Printf("[remote] failed to pair a device: %v", err)
		return serverutil.InternalServerError(errPairDevice)
	}
	return serverutil.Ok().WithData(PairDeviceResponse(result))
}

var pairDeviceRoute = serverutil.ApiRoute("POST", "/settings/remote-access/devices", pairDevice)
