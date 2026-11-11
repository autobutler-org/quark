package v0_admin

import (
	"github.com/autobutler-org/quark/pkg/util/restartutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getRestartStatus godoc
// @Summary Get whether Quark can restart itself
// @Description Whether restarting Quark would bring it back, and why not when it would not: not_supervised (it is not the installed service and QUARK_RESTART_SUPERVISED is not set, so nothing would start it again). Admin-only.
// @Tags admin
// @Produce json
// @Success 200 {object} restartStatusResponse
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/restart [get]
func getRestartStatus(_ *gin.Context) *serverutil.Response {
	result, err := restartutil.GetStatus(restartutil.GetStatusParams{})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(restartStatusResponse{
		Available: result.Available,
		Reason:    string(result.Reason),
	})
}

var getRestartStatusRoute = serverutil.ApiRoute("GET", "/admin/restart", getRestartStatus)
