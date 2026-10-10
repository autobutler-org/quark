package v0_hostname

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/hostnameutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getHostname godoc
// @Summary Get the device hostname
// @Description The device's hostname, the name it answers to on the local network when that differs (another device already had the name, so Avahi took the next free one), and whether this Quark can be renamed. A Quark that is not the installed Linux service reports available false with a reason. Admin-only.
// @Tags hostname
// @Produce json
// @Success 200 {object} hostnameResponse
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /hostname [get]
func getHostname(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	result, err := hostnameutil.GetHostname(c.Request.Context(), hostnameutil.GetHostnameParams{System: deps.HostnameSystem()})
	if err != nil {
		return hostnameErrorResponse(err)
	}
	return serverutil.Ok().WithData(hostnameResponse{
		Available:          result.Available,
		Reason:             string(result.Reason),
		Hostname:           result.Hostname,
		AdvertisedHostname: result.AdvertisedHostname,
	})
}

var getHostnameRoute = serverutil.ApiRoute("GET", "/hostname", getHostname)
