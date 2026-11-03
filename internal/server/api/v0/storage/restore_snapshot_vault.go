package v0_storage

import (
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// restoreSnapshotVault godoc
// @Summary Restore every account's vault from a snapshot backup
// @Description Re-confirms the caller with password, which carries the auth key of the admin's login password, exactly as DELETE /vault takes it; a wrong or missing key is a 403, a raw password is a 426, and nothing is restored. Shares the sign-in rate limit, and the body is at most 1 KiB.
// @Description Then restores the vault backup a snapshot wrote to the drive, which must have the snapshot-backup role, each vault under the account of the same
// @Description username, letter for letter. Refused while any vault has items, when an account the backup has a vault for already has a vault key here (a restore never replaces one),
// @Description when a backed-up vault has no account of its username here, and when a backed-up key or item would be refused as an API write. Every refusal names the accounts and changes nothing.
// @Description restoredAccounts names every account that got a vault back, and each is sent vault_changed. backupPasswordAccounts names the accounts whose vault opens with the
// @Description password they had when the backup was taken, as every vault restored onto new hardware does. Every attempt past the password check is written to the server log.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body restoreSnapshotVaultBody true "The backup drive and the admin's auth key"
// @Success 200 {object} backup.VaultImportResult
// @Failure 400 {object} serverutil.Response "bad request, a drive without the snapshot-backup role, a backup this version cannot read, or a backed-up key or item this Quark does not accept"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "password is not the caller's auth key"
// @Failure 404 {object} serverutil.Response "the device is not attached, or holds no vault backup"
// @Failure 409 {object} serverutil.Response "a vault already has items, an account already has a vault key, or a backed-up vault has no account"
// @Failure 413 {object} serverutil.Response "a body over 1 KiB"
// @Failure 426 {object} serverutil.Response "password is a raw password: the app is too old"
// @Failure 429 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Failure 501 {object} serverutil.Response "the Quark runs on PostgreSQL"
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/restore-vault [post]
func restoreSnapshotVault(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxRestoreVaultRequestBytes)
	var req restoreSnapshotVaultBody
	if err := c.ShouldBindJSON(&req); err != nil {
		if _, tooLarge := errors.AsType[*http.MaxBytesError](err); tooLarge {
			return serverutil.NewResponse().WithStatusCode(http.StatusRequestEntityTooLarge).
				WithError(errors.New("request body too large"))
		}
		return serverutil.BadRequest(fmt.Errorf("invalid request: %w", err))
	}

	// Nothing goes before this: a restore puts a vault under every account.
	username, _ := ctxutil.Get[string](c, "username")
	if failed := reconfirmAdmin(c, deps, username, req.Password); failed != nil {
		return failed
	}
	adminID, _ := ctxutil.Get[int64](c, "userID")

	result, err := backup.RestoreVault(backup.RestoreVaultParams{
		Ctx:          c.Request.Context(),
		LiveDB:       deps.Database().Db,
		Queries:      deps.Database().Queries,
		Registry:     deps.VFSRegistry(),
		DeviceSerial: req.DeviceSerial,
	})
	// Audited to the log, as the account deletion is, whichever way it ends.
	if err != nil {
		slog.Warn("vault restore from snapshot backup refused",
			"adminId", adminID, "admin", username, "deviceSerial", req.DeviceSerial, "error", err)
	} else {
		slog.Warn("vault restored from snapshot backup",
			"adminId", adminID, "admin", username, "deviceSerial", req.DeviceSerial,
			"accounts", result.RestoredAccounts, "items", result.Items)
	}

	var notFound *fileutil.NotFoundError
	switch {
	case errors.As(err, &notFound), errors.Is(err, fs.ErrNotExist):
		return serverutil.NotFound(err)
	case errors.Is(err, backup.ErrVaultNotEmpty), errors.Is(err, backup.ErrVaultAccountMissing),
		errors.Is(err, backup.ErrVaultKeyExists):
		return serverutil.Conflict(err)
	case errors.Is(err, backup.ErrVaultBackupVersion), errors.Is(err, backup.ErrVaultBackupInvalid),
		errors.Is(err, backup.ErrVaultRestoreRoleRequired):
		return serverutil.BadRequest(err)
	case errors.Is(err, backup.ErrDatabaseBackedUpSeparately):
		return serverutil.NewResponse().WithStatusCode(http.StatusNotImplemented).WithError(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	// Every session open on a restored account holds what it had before, if
	// anything; this is its cue to load the restored vault.
	for _, userID := range result.RestoredUserIDs {
		vaultutil.PublishChanged(vaultutil.PublishChangedParams{EventBus: deps.EventBus(), UserID: userID})
	}
	return serverutil.Ok().WithData(result)
}

// restoreSnapshotVaultBody is what the vault restore reads.
type restoreSnapshotVaultBody struct {
	DeviceSerial string `json:"deviceSerial" binding:"required"`
	// Password is the standard base64 auth key of the admin's login
	// password, as DELETE /vault takes it.
	Password string `json:"password"`
}

// maxRestoreVaultRequestBytes bounds the restore's body, a serial and an
// auth key.
const maxRestoreVaultRequestBytes = 1 << 10

// reconfirmAdmin checks that password is the auth key of the caller's login
// password, as DELETE /vault and PUT /vault/key do (#3615), so a session
// alone cannot restore a vault. A wrong or empty key is a 403 and a raw
// password a 426; nil means it matched.
func reconfirmAdmin(c *gin.Context, deps deputil.Dependencies, username, password string) *serverutil.Response {
	_, err := authutil.VerifyPassword(c.Request.Context(), authutil.VerifyPasswordParams{
		Queries:  deps.Database().Queries,
		Username: username,
		Password: password,
	})
	switch {
	case err == nil:
		return nil
	case errors.Is(err, authutil.ErrIncorrectPassword):
		return serverutil.NewResponse().WithStatusCode(http.StatusForbidden).WithError(err)
	case errors.Is(err, authutil.ErrUserNotFound):
		return serverutil.Unauthorized(errors.New("not authenticated"))
	default:
		// ErrAppTooOld is a 426 HttpError, whatever status this names.
		return serverutil.InternalServerError(err)
	}
}

var restoreSnapshotVaultRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/snapshot-backup/restore-vault", restoreSnapshotVault,
)
