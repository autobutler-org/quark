package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getRemoteAccessPaths godoc
// @Summary Get remote access paths
// @Description Admin-only debugging aid (#3883): for each device on remote access, whether its traffic to the Quark goes direct or through a relay, the relay region, the last handshake and byte counts, plus the Quark's network check (UDP, NAT mapping behavior, router port mapping, preferred relay and its latency). The check is the last one the Quark ran unless refresh is true, which runs a new one and waits up to 10 seconds for it. Holds no keys, names or addresses.
// @Tags settings
// @Produce json
// @Param refresh query bool false "Run a new network check before answering"
// @Success 200 {object} remoteutil.PathReportResult
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/remote-access/paths [get]
func getRemoteAccessPaths(c *gin.Context) *serverutil.Response {
	report, err := remoteutil.PathReport(remoteutil.PathReportParams{
		RefreshNetwork: c.Query("refresh") == "true",
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(report)
}

var getRemoteAccessPathsRoute = serverutil.ApiRoute("GET", "/settings/remote-access/paths", getRemoteAccessPaths)
