package v0_ssh

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
)

// clearSSHPassword godoc
// @Summary Clear the SSH login password
// @Description Removes the quark login account's password, so only allowed keys can sign in. Admin-only.
// @Tags ssh
// @Success 200
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "SSH access can't be managed on this Quark"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /ssh/password [delete]
func clearSSHPassword(c *gin.Context) *serverutil.Response {
	system, errResp := sshSystem(c)
	if errResp != nil {
		return errResp
	}
	if _, err := sshutil.ClearPassword(c.Request.Context(), sshutil.ClearPasswordParams{System: system}); err != nil {
		return sshErrorResponse(err)
	}
	return serverutil.Ok()
}

var clearSSHPasswordRoute = serverutil.ApiRoute("DELETE", "/ssh/password", clearSSHPassword)
