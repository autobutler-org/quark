package v0_vault

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// importVaultBackup godoc
// @Summary Import a vault backup from a device
// @Description Reads the encrypted backup on a managed device, unlocks it with its recovery password, and merges it in.
// @Tags vault
// @Accept json
// @Produce json
// @Param body body importBackupRequest true "Device serial and recovery password"
// @Success 200 {object} vaultutil.ImportResult
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 423 {object} serverutil.Response "Vault is locked"
// @Failure 503 {object} serverutil.Response "Vault storage device is disconnected"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/import-backup [post]
func importVaultBackup(c *gin.Context) *serverutil.Response {
	deps, liveKey, errResp := requireUnlockedVault(c)
	if errResp != nil {
		return errResp
	}
	defer vaultcrypto.ZeroKey(liveKey)

	var req importBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	dev, err := deps.StorageService().FindManagedDeviceBySerial(req.DeviceSerial)
	if err != nil || dev == nil {
		return serverutil.BadRequest(fmt.Errorf("device not found or not managed"))
	}

	result, err := vaultutil.ImportBackup(c.Request.Context(), vaultutil.ImportBackupParams{
		VaultDB:          deps.VaultDB(),
		LiveKey:          liveKey,
		RecoveryPassword: req.RecoveryPassword,
		BackupDir:        dev.FilesDir,
	})
	if errors.Is(err, vaultutil.ErrBackupImportFailed) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(result.Import)
}

var importVaultBackupRoute = serverutil.ApiRoute("POST", "/vault/import-backup", importVaultBackup)
