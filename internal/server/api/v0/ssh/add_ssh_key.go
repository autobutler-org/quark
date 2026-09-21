package v0_ssh

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"

	"github.com/gin-gonic/gin"
)

// addSSHKey godoc
// @Summary Allow a public key to sign in over SSH
// @Description Adds one OpenSSH public key to those allowed to sign in as quark. Options such as command= are dropped. Admin-only.
// @Tags ssh
// @Accept json
// @Produce json
// @Param body body addSSHKeyBody true "The public key"
// @Success 201 {object} sshutil.Key
// @Failure 400 {object} serverutil.Response "not an SSH public key"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "the key is already allowed, or SSH access can't be managed on this Quark"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /ssh/keys [post]
func addSSHKey(c *gin.Context) *serverutil.Response {
	system, errResp := sshSystem(c)
	if errResp != nil {
		return errResp
	}
	var req addSSHKeyBody
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(err)
	}
	result, err := sshutil.AddKey(sshutil.AddKeyParams{System: system, Key: req.Key})
	if err != nil {
		return sshErrorResponse(err)
	}
	return serverutil.Ok().WithStatusCode(http.StatusCreated).WithData(result.Key)
}

var addSSHKeyRoute = serverutil.ApiRoute("POST", "/ssh/keys", addSSHKey)
