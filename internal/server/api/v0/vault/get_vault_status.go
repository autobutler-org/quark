package v0_vault

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// getVaultStatus godoc
// @Summary Get vault status
// @Description Reports whether the vault is initialized and unlocked, its auto-lock window, and which device holds it.
// @Tags vault
// @Produce json
// @Success 200 {object} vaultStatusResponse
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/status [get]
func getVaultStatus(c *gin.Context) *serverutil.Response {
	deps, errResp := getDeps(c)
	if errResp != nil {
		return errResp
	}

	result, err := vaultutil.Status(c.Request.Context(), vaultutil.StatusParams{
		VaultQueries: deps.VaultDB().Queries,
		MainQueries:  deps.Database().Queries,
		Session:      deps.VaultSession(),
		Storage:      deps.StorageService(),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(vaultStatusResponse{
		Initialized:     result.Initialized,
		Locked:          result.Locked,
		AutoLockSeconds: result.AutoLockSeconds,
		StorageDevice:   result.StorageDevice,
		DeviceConnected: result.DeviceConnected,
		LockReason:      result.LockReason,
	})
}

var getVaultStatusRoute = serverutil.ApiRoute("GET", "/vault/status", getVaultStatus)
