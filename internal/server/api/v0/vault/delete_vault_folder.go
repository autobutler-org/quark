package v0_vault

import (
	"fmt"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// deleteVaultFolder godoc
// @Summary Delete a vault folder
// @Description Removes one folder.
// @Tags vault
// @Produce json
// @Param id path int true "Folder ID"
// @Success 200 {object} object "deleted flag"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 423 {object} serverutil.Response "Vault is locked"
// @Failure 503 {object} serverutil.Response "Vault storage device is disconnected"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/folders/{id} [delete]
func deleteVaultFolder(c *gin.Context) *serverutil.Response {
	deps, key, errResp := requireUnlockedVault(c)
	if errResp != nil {
		return errResp
	}
	defer vaultcrypto.ZeroKey(key)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid id"))
	}

	result, err := vaultutil.DeleteFolder(c.Request.Context(), vaultutil.DeleteFolderParams{
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

var deleteVaultFolderRoute = serverutil.ApiRoute("DELETE", "/vault/folders/:id", deleteVaultFolder)
