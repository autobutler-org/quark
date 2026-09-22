package v0_vault

import (
	"errors"
	"fmt"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// getVaultEntry godoc
// @Summary Get a decrypted vault entry
// @Description Decrypts and returns one entry in full, including its password. Requires the vault unlocked.
// @Tags vault
// @Produce json
// @Param id path int true "Entry ID"
// @Success 200 {object} vaultutil.EntryDetail
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 423 {object} serverutil.Response "Vault is locked"
// @Failure 503 {object} serverutil.Response "Vault storage device is disconnected"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/entries/{id} [get]
func getVaultEntry(c *gin.Context) *serverutil.Response {
	deps, key, errResp := requireUnlockedVault(c)
	if errResp != nil {
		return errResp
	}
	defer vaultcrypto.ZeroKey(key)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid id"))
	}

	result, err := vaultutil.GetEntry(c.Request.Context(), vaultutil.GetEntryParams{
		Queries: deps.VaultDB().Queries,
		Key:     key,
		ID:      id,
	})
	if errors.Is(err, vaultutil.ErrEntryNotFound) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result.Entry)
}

var getVaultEntryRoute = serverutil.ApiRoute("GET", "/vault/entries/:id", getVaultEntry)
