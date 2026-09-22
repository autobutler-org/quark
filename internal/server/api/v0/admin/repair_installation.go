package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/repairutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// repairInstallation godoc
// @Summary Repair the installation
// @Description Restarts Quark so the service reapplies its system setup as root before it starts again. The response goes out first; the process exits about two seconds later and is unavailable for a few seconds. Admin-only.
// @Tags admin
// @Success 200
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "The installation can't be repaired from Quark on this device"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/repair [post]
func repairInstallation(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	if _, err := repairutil.Repair(repairutil.RepairParams{System: deps.RepairSystem()}); err != nil {
		if errors.Is(err, repairutil.ErrUnavailable) {
			return serverutil.Conflict(err)
		}
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok()
}

var repairInstallationRoute = serverutil.ApiRoute("POST", "/admin/repair", repairInstallation)
