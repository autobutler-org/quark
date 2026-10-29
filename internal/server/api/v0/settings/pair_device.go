package v0_settings

import (
	"errors"
	"log"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// errPairDevice is what the client reads when the provisioning service could
// not mint a key. The Go error goes to the log.
var errPairDevice = errors.New("the Quark could not get a key for this device, the Quark's log has the details")

// pairDevice godoc
// @Summary Pair a device for remote access
// @Description Mints a single-use pre-auth key that adds the caller's device, such as a phone, to this Quark's Headscale household, and returns what the device needs to join the tailnet and reach the Quark. Any signed-in user may call it, a few times an hour. 409 when the Quark is on the user's own tailnet, when remote access is off, or when the Quark has no household to add to; 503 while remote access is still connecting.
// @Tags settings
// @Produce json
// @Success 200 {object} PairDeviceResponse
// @Failure 401 {object} serverutil.Response "Unauthorized"
// @Failure 409 {object} serverutil.Response "Custom tailnet, remote access off, or no household"
// @Failure 429 {object} serverutil.Response "This account has asked for too many keys recently"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Failure 503 {object} serverutil.Response "Remote access is still connecting"
// @Security BearerAuth
// @Router /settings/remote-access/devices [post]
func pairDevice(c *gin.Context) *serverutil.Response {
	username, ok := ctxutil.Get[string](c, "username")
	if !ok || username == "" {
		return serverutil.Unauthorized(errors.New("authentication required"))
	}
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(errors.New("dependencies unavailable"))
	}
	result, err := remoteutil.PairDevice(remoteutil.PairDeviceParams{
		Account: username,
		Limiter: deps.PairDeviceRateLimiter(),
	})
	switch {
	case errors.Is(err, remoteutil.ErrCustomTailnet),
		errors.Is(err, remoteutil.ErrRemoteAccessOff),
		errors.Is(err, remoteutil.ErrNoHousehold):
		return serverutil.Conflict(err)
	case errors.Is(err, remoteutil.ErrNotConnected):
		return serverutil.ServiceUnavailable(err)
	case errors.Is(err, remoteutil.ErrTooManyPairs):
		return serverutil.NewResponse().WithStatusCode(http.StatusTooManyRequests).WithError(err)
	case err != nil:
		log.Printf("[remote] failed to pair a device: %v", err)
		return serverutil.InternalServerError(errPairDevice)
	}
	return serverutil.Ok().WithData(PairDeviceResponse(result))
}

var pairDeviceRoute = serverutil.ApiRoute("POST", "/settings/remote-access/devices", pairDevice)
