package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getRemoteAccessPaths godoc
// @Summary Get remote access paths
// @Description Admin-only debugging aid (#3883): for each device on remote access, whether its traffic to the Quark goes direct or through a relay, the relay region, the last handshake and byte counts, plus the Quark's last network check (UDP, NAT mapping behavior, router port mapping, preferred relay and its latency). Holds no keys, names or addresses.
// @Tags settings
// @Produce json
// @Success 200 {object} remoteutil.PathReportResult
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/remote-access/paths [get]
func getRemoteAccessPaths(c *gin.Context) *serverutil.Response {
	report, err := remoteutil.PathReport()
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(report)
}

var getRemoteAccessPathsRoute = serverutil.ApiRoute("GET", "/settings/remote-access/paths", getRemoteAccessPaths)
