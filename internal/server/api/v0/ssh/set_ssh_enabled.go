package v0_ssh

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
)

// setSSHEnabled godoc
// @Summary Turn SSH access on or off
// @Description Starts sshd and opens port 22, or stops sshd and closes the port. The choice survives a reboot. Admin-only.
// @Tags ssh
// @Accept json
// @Param body body setSSHEnabledBody true "Whether SSH access should be on"
// @Success 200
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "SSH access can't be managed on this Quark"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /ssh/enabled [put]
func setSSHEnabled(c *gin.Context) *serverutil.Response {
	system, errResp := sshSystem(c)
	if errResp != nil {
		return errResp
	}
	var req setSSHEnabledBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	if _, err := sshutil.SetEnabled(c.Request.Context(), sshutil.SetEnabledParams{System: system, Enabled: *req.Enabled}); err != nil {
		return sshErrorResponse(err)
	}
	return serverutil.Ok()
}

var setSSHEnabledRoute = serverutil.ApiRoute("PUT", "/ssh/enabled", setSSHEnabled)
