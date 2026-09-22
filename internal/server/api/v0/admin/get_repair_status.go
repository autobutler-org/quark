package v0_admin

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/repairutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// getRepairStatus godoc
// @Summary Get whether the installation can be repaired
// @Description Whether restarting Quark would reapply its system setup, and why not when it would not: unsupported_os, not_service, or unit_outdated (the installed unit predates the setup step; a one-time `sudo quark install` fixes that). Admin-only.
// @Tags admin
// @Produce json
// @Success 200 {object} repairStatusResponse
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/repair [get]
func getRepairStatus(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	result, err := repairutil.GetStatus(repairutil.GetStatusParams{System: deps.RepairSystem()})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(repairStatusResponse{
		Available: result.Available,
		Reason:    string(result.Reason),
	})
}

var getRepairStatusRoute = serverutil.ApiRoute("GET", "/admin/repair", getRepairStatus)
