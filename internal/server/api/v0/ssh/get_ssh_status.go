package v0_ssh

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
)

// getSSHStatus godoc
// @Summary Get SSH access status
// @Description Whether SSH access can be managed on this Quark (and why not), whether sshd is running, and the public keys allowed to sign in as quark. Admin-only.
// @Tags ssh
// @Produce json
// @Success 200 {object} sshStatusResponse
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /ssh/status [get]
func getSSHStatus(c *gin.Context) *serverutil.Response {
	system, errResp := sshSystem(c)
	if errResp != nil {
		return errResp
	}
	result, err := sshutil.GetStatus(c.Request.Context(), sshutil.GetStatusParams{System: system})
	if err != nil {
		return sshErrorResponse(err)
	}
	keys := result.Keys
	if keys == nil {
		keys = []sshutil.Key{}
	}
	return serverutil.Ok().WithData(sshStatusResponse{
		Available: result.Available,
		Reason:    string(result.Reason),
		Enabled:   result.Enabled,
		Keys:      keys,
	})
}

var getSSHStatusRoute = serverutil.ApiRoute("GET", "/ssh/status", getSSHStatus)
