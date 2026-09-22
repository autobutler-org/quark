package v0_vault

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// setupVault godoc
// @Summary Initialize the vault
// @Description Creates the vault with a master password and leaves it unlocked. Fails if it already exists.
// @Tags vault
// @Accept json
// @Produce json
// @Param body body setupRequest true "Master password"
// @Success 200 {object} object "initialized and locked flags"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/setup [post]
func setupVault(c *gin.Context) *serverutil.Response {
	deps, errResp := getDeps(c)
	if errResp != nil {
		return errResp
	}

	var req setupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	result, err := vaultutil.Setup(c.Request.Context(), vaultutil.SetupParams{
		Queries:        deps.VaultDB().Queries,
		Session:        deps.VaultSession(),
		MasterPassword: req.MasterPassword,
	})
	switch {
	case errors.Is(err, vaultutil.ErrVaultAlreadyInitialized),
		errors.Is(err, vaultutil.ErrMasterPasswordTooShort):
		return serverutil.BadRequest(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"initialized": result.Initialized,
		"locked":      result.Locked,
	})
}

var setupVaultRoute = serverutil.ApiRoute("POST", "/vault/setup", setupVault)
