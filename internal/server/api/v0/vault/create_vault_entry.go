package v0_vault

import (
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// createVaultEntry godoc
// @Summary Create a vault entry
// @Description Encrypts a new entry with the unlocked vault key and stores it.
// @Tags vault
// @Accept json
// @Produce json
// @Param body body createEntryRequest true "Entry fields"
// @Success 200 {object} vaultutil.EntryDetail
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 423 {object} serverutil.Response "Vault is locked"
// @Failure 503 {object} serverutil.Response "Vault storage device is disconnected"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/entries [post]
func createVaultEntry(c *gin.Context) *serverutil.Response {
	deps, key, errResp := requireUnlockedVault(c)
	if errResp != nil {
		return errResp
	}
	defer vaultcrypto.ZeroKey(key)

	var req createEntryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	result, err := vaultutil.CreateEntry(c.Request.Context(), vaultutil.CreateEntryParams{
		Queries: deps.VaultDB().Queries,
		Key:     key,
		Fields:  req.fields(),
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(result.Entry)
}

var createVaultEntryRoute = serverutil.ApiRoute("POST", "/vault/entries", createVaultEntry)
