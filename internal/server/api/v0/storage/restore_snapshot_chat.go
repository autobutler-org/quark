package v0_storage

import (
	"errors"
	"io/fs"
	"log/slog"
	"net/http"

	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// restoreSnapshotChat godoc
// @Summary Restore the chat from a snapshot backup
// @Description Re-confirms the caller with password, which carries the auth key of the admin's login password, exactly as POST /storage/devices/snapshot-backup/restore-vault takes it; a wrong or missing key is a 403, a raw password is a 426, and nothing is restored. Shares the sign-in rate limit, and the body is at most 1 KiB.
// @Description Then restores the chat backup a snapshot wrote into one run on the drive, which must have the snapshot-backup role: run, a folder under backups/, or the newest complete run when it is empty. The answer names the run.
// @Description The restore replaces an empty chat: one with no message and no channel but general. A chat that already has messages or channels is refused, and a refused or failed restore changes nothing.
// @Description The backup does not carry accounts. Every account it names is matched by username on this Quark; unmatchedUsers names the ones that are not here, whose messages stay with no author and whose memberships, reactions and chat keys are not restored.
// @Description Also refused, changing nothing, when this Quark did not write the backup: its MAC is another Quark's, the file changed after the snapshot, or its MAC is gone from a drive this Quark binds its snapshots to. A snapshot taken before binding still restores.
// @Description Every channel's members are sent chat_channel_changed. Every attempt past the password check is written to the server log.
// @Tags storage
// @Accept json
// @Produce json
// @Param body body restoreSnapshotBody true "The backup drive, the run, and the admin's auth key"
// @Success 200 {object} backup.ChatImportResult
// @Failure 400 {object} serverutil.Response "bad request, a drive without the snapshot-backup role, a backup this version cannot read, or a backup this Quark did not write"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "password is not the caller's auth key"
// @Failure 404 {object} serverutil.Response "the device is not attached, holds no complete run or none of that name, or the run holds no chat backup"
// @Failure 409 {object} serverutil.Response "the chat already has messages or channels"
// @Failure 413 {object} serverutil.Response "a body over 1 KiB"
// @Failure 426 {object} serverutil.Response "password is a raw password: the app is too old"
// @Failure 429 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response
// @Failure 501 {object} serverutil.Response "the Quark runs on PostgreSQL"
// @Security BearerAuth
// @Router /storage/devices/snapshot-backup/restore-chat [post]
func restoreSnapshotChat(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok || deps.Database() == nil {
		return serverutil.InternalServerError(nil)
	}

	// Nothing goes before this: a restore replaces every account's chat keys.
	req, failed := confirmRestore(c, deps)
	if failed != nil {
		return failed
	}
	username, _ := ctxutil.Get[string](c, "username")
	adminID, _ := ctxutil.Get[int64](c, "userID")

	result, err := backup.RestoreChat(backup.RestoreChatParams{
		Ctx:          c.Request.Context(),
		LiveDB:       deps.Database().Db,
		Queries:      deps.Database().Queries,
		Registry:     deps.VFSRegistry(),
		DeviceSerial: req.DeviceSerial,
		Run:          req.Run,
	})
	// Audited to the log, as the vault restore is, whichever way it ends.
	if err != nil {
		slog.Warn("chat restore from snapshot backup refused",
			"adminId", adminID, "admin", username, "deviceSerial", req.DeviceSerial, "run", req.Run, "error", err)
	} else {
		slog.Warn("chat restored from snapshot backup",
			"adminId", adminID, "admin", username, "deviceSerial", req.DeviceSerial, "run", result.Run,
			"channels", result.Channels, "messages", result.Messages, "unmatchedUsers", result.UnmatchedUsers)
	}

	var notFound *fileutil.NotFoundError
	switch {
	case errors.As(err, &notFound), errors.Is(err, fs.ErrNotExist), errors.Is(err, backup.ErrNoSnapshot),
		errors.Is(err, backup.ErrRunNotFound):
		return serverutil.NotFound(err)
	case errors.Is(err, backup.ErrChatNotEmpty):
		return serverutil.Conflict(err)
	case errors.Is(err, backup.ErrChatBackupVersion), errors.Is(err, backup.ErrChatRestoreRoleRequired),
		errors.Is(err, backup.ErrBackupNotFromThisQuark):
		return serverutil.BadRequest(err)
	case errors.Is(err, backup.ErrDatabaseBackedUpSeparately):
		return serverutil.NewResponse().WithStatusCode(http.StatusNotImplemented).WithError(err)
	case err != nil:
		return serverutil.InternalServerError(err)
	}

	// The restore is committed: a failure to tell the clients leaves them
	// to their next reload, not the request.
	if err := chatutil.PublishChannelsChanged(chatutil.PublishChannelsChangedParams{
		Ctx: c.Request.Context(), Database: deps.Database(), EventBus: deps.EventBus(),
	}); err != nil {
		slog.Warn("chat restored, but its channels could not be announced", "error", err)
	}
	return serverutil.Ok().WithData(result)
}

var restoreSnapshotChatRoute = serverutil.ApiRoute(
	"POST", "/storage/devices/snapshot-backup/restore-chat", restoreSnapshotChat,
)
