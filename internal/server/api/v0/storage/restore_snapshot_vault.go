package v0_storage

import (
	"errors"
	"fmt"
	"io/fs"
	"net/http"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// restoreSnapshotVault godoc
// @Summary Restore every account's vault from a snapshot backup
// @Description Restores the vault backup a snapshot wrote to the drive, each vault under the account of the same
// @Description username, letter for letter. Refused while any vault has items, and when a backed-up vault has no
// @Description account of its username here. backupPasswordAccounts names the accounts whose vault opens with the
// @Description password they had when the backup was taken, as every vault restored onto new hardware does.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body object true "{deviceSerial: string}"
// @Success 200 {object} backup.VaultImportResult
// @Failure 400 {object} serverutil.Response "bad request, or a backup this version cannot read"
// @Failure 404 {object} serverutil.Response "the device is not attached, or holds no vault backup"
// @Failure 409 {object} serverutil.Response "a vault already has items, or a backed-up vault has no account"
// @Failure 500 {object} serverutil.Response
// @Failure 501 {object} serverutil.Response "the Quark runs on PostgreSQL"
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/restore-vault [post]
func restoreSnapshotVault(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	var req struct {
		DeviceSerial string `json:"deviceSerial" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	result, err := backup.RestoreVault(backup.RestoreVaultParams{
		Ctx:          c.Request.Context(),
		LiveDB:       deps.Database().Db,
		Registry:     deps.VFSRegistry(),
		DeviceSerial: req.DeviceSerial,
	})
	var notFound *fileutil.NotFoundError
	switch {
	case errors.As(err, &notFound), errors.Is(err, fs.ErrNotExist):
		return serverutil.NotFound(err)
	case errors.Is(err, backup.ErrVaultNotEmpty), errors.Is(err, backup.ErrVaultAccountMissing):
		return serverutil.Conflict(err)
	case errors.Is(err, backup.ErrVaultBackupVersion):
		return serverutil.BadRequest(err)
	case errors.Is(err, backup.ErrDatabaseBackedUpSeparately):
		return serverutil.NewResponse().WithStatusCode(http.StatusNotImplemented).WithError(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithData(result)
}

var restoreSnapshotVaultRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/snapshot-backup/restore-vault", restoreSnapshotVault,
)
