package v0_ssh

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
)

// removeSSHKey godoc
// @Summary Stop a public key signing in over SSH
// @Description Removes the allowed key with the given SHA256 fingerprint. The fingerprint is a query parameter because it can contain a slash. Admin-only.
// @Tags ssh
// @Param fingerprint query string true "SHA256 fingerprint, as SHA256:..."
// @Success 200
// @Failure 400 {object} serverutil.Response
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no allowed key has that fingerprint"
// @Failure 409 {object} serverutil.Response "SSH access can't be managed on this Quark"
// @Failure 500 {object} serverutil.Response
// @Router /ssh/keys [delete]
func removeSSHKey(c *gin.Context) *serverutil.Response {
	system, errResp := sshSystem(c)
	if errResp != nil {
		return errResp
	}
	fingerprint := c.Query("fingerprint")
	if fingerprint == "" {
		return serverutil.BadRequest(errors.New("fingerprint is required"))
	}
	if _, err := sshutil.RemoveKey(sshutil.RemoveKeyParams{System: system, Fingerprint: fingerprint}); err != nil {
		return sshErrorResponse(err)
	}
	return serverutil.Ok()
}

var removeSSHKeyRoute = serverutil.ApiRoute("DELETE", "/ssh/keys", removeSSHKey)
