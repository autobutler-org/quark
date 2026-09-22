package v0_vault

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// importVault godoc
// @Summary Import entries from a file
// @Description Takes an uploaded export and writes its entries in. Existing name plus host matches are skipped, not duplicated.
// @Tags vault
// @Accept mpfd
// @Produce json
// @Param file formData file true "Export file"
// @Param format formData string false "Source format; sniffed from the bytes when absent"
// @Success 200 {object} vaultutil.ImportResult
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 423 {object} serverutil.Response "Vault is locked"
// @Failure 503 {object} serverutil.Response "Vault storage device is disconnected"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/import [post]
func importVault(c *gin.Context) *serverutil.Response {
	deps, key, errResp := requireUnlockedVault(c)
	if errResp != nil {
		return errResp
	}
	defer vaultcrypto.ZeroKey(key)

	file, _, err := c.Request.FormFile("file")
	if err != nil {
		return serverutil.BadRequest(fmt.Errorf("file required: %w", err))
	}
	defer file.Close()

	data, err := vaultutil.ReadImport(file)
	if errors.Is(err, vaultutil.ErrImportTooLarge) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.InternalServerError(fmt.Errorf("read file: %w", err))
	}

	format := c.DefaultPostForm("format", vaultutil.FormatAuto)

	result, err := vaultutil.Import(c.Request.Context(), vaultutil.ImportParams{
		VaultDB: deps.VaultDB(),
		Key:     key,
		Data:    data,
		Format:  format,
	})
	if errors.Is(err, vaultutil.ErrUnsupportedImportFormat) {
		return serverutil.BadRequest(fmt.Errorf("unsupported format: %s", format))
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(result)
}

var importVaultRoute = serverutil.ApiRoute("POST", "/vault/import", importVault)
