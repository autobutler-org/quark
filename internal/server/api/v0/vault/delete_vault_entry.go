package v0_vault

import (
	"fmt"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// deleteVaultEntry godoc
// @Summary Delete a vault entry
// @Description Removes one entry from the vault.
// @Tags vault
// @Produce json
// @Param id path int true "Entry ID"
// @Success 200 {object} object "deleted flag"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 423 {object} serverutil.Response "Vault is locked"
// @Failure 503 {object} serverutil.Response "Vault storage device is disconnected"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/entries/{id} [delete]
func deleteVaultEntry(c *gin.Context) *serverutil.Response {
	deps, key, errResp := requireUnlockedVault(c)
	if errResp != nil {
		return errResp
	}
	defer vaultcrypto.ZeroKey(key)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid id"))
	}

	result, err := vaultutil.DeleteEntry(c.Request.Context(), vaultutil.DeleteEntryParams{
		Queries: deps.VaultDB().Queries,
		ID:      id,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"deleted": result.Deleted,
	})
}

var deleteVaultEntryRoute = serverutil.ApiRoute("DELETE", "/vault/entries/:id", deleteVaultEntry)
