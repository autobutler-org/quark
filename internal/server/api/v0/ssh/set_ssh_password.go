package v0_ssh

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
)

// setSSHPassword godoc
// @Summary Set the SSH login password
// @Description Sets the password for the quark login account. Quark does not store it. At least 12 characters, no control characters. Admin-only.
// @Tags ssh
// @Accept json
// @Param body body setSSHPasswordBody true "The new password"
// @Success 200
// @Failure 400 {object} serverutil.Response "too short, too long, or holds control characters"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "SSH access can't be managed on this Quark"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /ssh/password [put]
func setSSHPassword(c *gin.Context) *serverutil.Response {
	system, errResp := sshSystem(c)
	if errResp != nil {
		return errResp
	}
	var req setSSHPasswordBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	if _, err := sshutil.SetPassword(c.Request.Context(), sshutil.SetPasswordParams{System: system, Password: req.Password}); err != nil {
		return sshErrorResponse(err)
	}
	return serverutil.Ok()
}

var setSSHPasswordRoute = serverutil.ApiRoute("PUT", "/ssh/password", setSSHPassword)
