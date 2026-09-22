package v0_vault

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// lockVault godoc
// @Summary Lock the vault
// @Description Drops the in-memory vault key immediately, before the auto-lock window expires.
// @Tags vault
// @Produce json
// @Success 200 {object} object "locked flag"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/lock [post]
func lockVault(c *gin.Context) *serverutil.Response {
	deps, errResp := getDeps(c)
	if errResp != nil {
		return errResp
	}

	deps.VaultSession().Lock()

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"locked": true,
	})
}

var lockVaultRoute = serverutil.ApiRoute("POST", "/vault/lock", lockVault)
