package v0_hostname

import (
	"fmt"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/hostnameutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// setHostname godoc
// @Summary Rename the device
// @Description Sets the device's hostname with no reboot, and publishes hostname_changed. The device then answers to the new name under .local, advertises itself as "Quark on" that name, and serves a regenerated TLS certificate that covers the new name, so an app that saved the old address has to move to the new one. hostname is one RFC 1123 label: 1 to 63 lowercase letters, digits or hyphens, with at least one letter and no hyphen at either end. advertisedHostname in the answer differs from hostname when another device already had the name; that can take a second to show, so read GET /hostname afterwards. Admin-only.
// @Tags hostname
// @Accept json
// @Produce json
// @Param body body setHostnameBody true "The new hostname"
// @Success 200 {object} hostnameResponse
// @Failure 400 {object} serverutil.Response "Not a valid hostname"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "This Quark can't be renamed"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /hostname [put]
func setHostname(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBodyBytes)
	var body setHostnameBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	result, err := hostnameutil.SetHostname(c.Request.Context(), hostnameutil.SetHostnameParams{
		System:   deps.HostnameSystem(),
		Hostname: body.Hostname,
	})
	if err != nil {
		return hostnameErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{
			Kind: eventbus.EventHostnameChanged,
			Data: eventbus.HostnameChanged{Hostname: result.Hostname, AdvertisedHostname: result.AdvertisedHostname},
		})
	}
	return serverutil.Ok().WithData(hostnameResponse{
		Available:          true,
		Hostname:           result.Hostname,
		AdvertisedHostname: result.AdvertisedHostname,
	})
}

var setHostnameRoute = serverutil.ApiRoute("PUT", "/hostname", setHostname)
