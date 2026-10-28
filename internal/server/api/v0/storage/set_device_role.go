package v0_storage

import (
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

// setDeviceRole godoc
// @Summary Set the role of a storage device
// @Description Assigns a role (default-storage, snapshot-backup, unassigned) to a device. Requires the caller's login password again. A drive whose health.verdict is replace-soon is refused with 409 unless acknowledgeHealth is true. Watch does not block. Unknown is not healthy. Files already on the drive are left in place. Switching default storage to a drive in worse health than the current one uses the stronger 409 text.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body object true "{serial: string, role: string, username: string, password: string, acknowledgeHealth: bool}"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "replace-soon drive was not acknowledged"
// @Failure 426 {object} serverutil.Response "password is a raw password, not the auth key: the app is too old"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/role [put]
func setDeviceRole(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		Serial            string `json:"serial"`
		Role              string `json:"role" binding:"required"`
		Username          string `json:"username" binding:"required"`
		Password          string `json:"password" binding:"required"`
		AcknowledgeHealth bool   `json:"acknowledgeHealth"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	sessionUser, sessionKnown := ctxutil.Get[string](c, "username")

	result, err := deviceutil.SetRole(deviceutil.SetRoleParams{
		Ctx:               c.Request.Context(),
		Queries:           deps.Database().Queries,
		Storage:           deps.StorageService(),
		Serial:            req.Serial,
		Role:              req.Role,
		Username:          req.Username,
		Password:          req.Password,
		SessionUsername:   sessionUser,
		SessionKnown:      sessionKnown,
		AcknowledgeHealth: req.AcknowledgeHealth,
	})
	if err != nil {
		return deviceError(err)
	}

	return serverutil.Ok().WithData(gin.H{
		"serial": result.Serial,
		"role":   result.Role,
	})
}

var setDeviceRoleRoute = serverutil.ApiRoute(
	"PUT", "/storage/devices/role", setDeviceRole,
)
