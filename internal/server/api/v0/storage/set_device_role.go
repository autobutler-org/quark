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
// @Description Assigns a role (default-storage, snapshot-backup, unassigned) to a device. Requires master password re-entry.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body object true "{serial: string, role: string, username: string, password: string}"
// @Success 200 {object} object
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /storage/devices/role [put]
func setDeviceRole(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		Serial   string `json:"serial"`
		Role     string `json:"role" binding:"required"`
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}

	sessionUser, sessionKnown := ctxutil.Get[string](c, "username")

	result, err := deviceutil.SetRole(deviceutil.SetRoleParams{
		Ctx:             c.Request.Context(),
		Queries:         deps.Database().Queries,
		Storage:         deps.StorageService(),
		Serial:          req.Serial,
		Role:            req.Role,
		Username:        req.Username,
		Password:        req.Password,
		SessionUsername: sessionUser,
		SessionKnown:    sessionKnown,
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
