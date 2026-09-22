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

// updateVaultEntry godoc
// @Summary Update a vault entry
// @Description Replaces an entry wholesale: any field omitted from the body is cleared, not kept.
// @Tags vault
// @Accept json
// @Produce json
// @Param id path int true "Entry ID"
// @Param body body createEntryRequest true "Replacement entry fields"
// @Success 200 {object} object "id of the updated entry"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 404 {object} serverutil.Response "Not Found"
// @Failure 423 {object} serverutil.Response "Vault is locked"
// @Failure 503 {object} serverutil.Response "Vault storage device is disconnected"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/entries/{id} [put]
func updateVaultEntry(c *gin.Context) *serverutil.Response {
	deps, key, errResp := requireUnlockedVault(c)
	if errResp != nil {
		return errResp
	}
	defer vaultcrypto.ZeroKey(key)

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid id"))
	}

	var req createEntryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	result, err := vaultutil.UpdateEntry(c.Request.Context(), vaultutil.UpdateEntryParams{
		Queries: deps.VaultDB().Queries,
		Key:     key,
		ID:      id,
		Fields:  req.fields(),
	})
	if errors.Is(err, vaultutil.ErrEntryNotFound) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"id": result.ID,
	})
}

var updateVaultEntryRoute = serverutil.ApiRoute("PUT", "/vault/entries/:id", updateVaultEntry)
