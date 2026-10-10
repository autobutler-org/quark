package backup

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"strconv"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// The failures a caller of [StartSnapshotBackup] can fix. Anything else it
// returns is the server's fault. The messages are the ones the client already
// reads, so they travel to the response unchanged.
var (
	ErrTargetRoleRequired       = errors.New("target device must have the snapshot-backup role")
	ErrTargetNotManaged         = errors.New("target device not found or not managed")
	ErrVaultCredentialsRequired = errors.New("username and password required for vault backup")
	ErrRecoveryPasswordTooShort = errors.New("recovery password must be at least 8 characters")
	ErrVaultNotInitialized      = errors.New("vault is not initialized")
)

// The failures that mean the credentials were wrong rather than the request.
var (
	ErrInvalidCredentials     = errors.New("invalid credentials")
	ErrMasterPasswordMismatch = errors.New("master password does not match vault")
)

// BackupInProgressError reports a target device that already has a backup
// running. The handler answers it with 409 and names the job holding the lock.
type BackupInProgressError struct {
	JobID string
}

func (e *BackupInProgressError) Error() string {
	return fmt.Sprintf("backup already running for this device (job %s)", e.JobID)
}

// StartSnapshotBackupParams starts a snapshot backup onto a target device. The
// vault half is opt-in: leave RecoveryPassword empty and no credentials are
// asked for and no vault export is written.
type StartSnapshotBackupParams struct {
	// Ctx bounds the checks made, and the vault export built, before the job
	// is queued. The backup itself runs on the job queue and outlives it.
	Ctx context.Context
	// Queries reads the device roles, the vault, and the job holding the
	// target's lock.
	Queries *db.Queries
	// Registry holds the target device's files namespace.
	Registry vfs.Registry
	// Queue runs the backup. Its Handler for [Kind] comes from [NewHandler].
	Queue *jobutil.Queue
	// UserID is the account starting the backup. 0 records none.
	UserID int64
	// TargetDeviceSerial is the device to back up onto. It must already hold
	// the snapshot-backup role.
	TargetDeviceSerial string
	// Username and Password authenticate the vault export, and are required
	// only when RecoveryPassword is set.
	Username string
	Password string
	// RecoveryPassword encrypts the exported vault. Empty skips the export.
	RecoveryPassword string
}

// StartSnapshotBackupResult reports the job that was queued. The backup is
// still running when this returns; [GetSnapshotBackupStatus] reads its
// progress.
type StartSnapshotBackupResult struct {
	JobID string
}

// StartSnapshotBackup validates the request and queues the backup as a job.
// One pending or running backup per target is all the jobs table allows, on
// every instance at once, so a second start returns a [BackupInProgressError].
//
// A vault export is built here, under a temp name on the target, and the job
// only moves it into place: the password and the vault key never leave the
// request, and whichever instance runs the job needs neither.
func StartSnapshotBackup(params StartSnapshotBackupParams) (StartSnapshotBackupResult, error) {
	ctx := params.Ctx

	role, err := params.Queries.GetDeviceRole(ctx, params.TargetDeviceSerial)
	if err != nil || role != "snapshot-backup" {
		return StartSnapshotBackupResult{}, ErrTargetRoleRequired
	}

	// The index is the lock. This only spares a request that is going to lose
	// to it the work of a vault export.
	if inProgress := activeBackup(ctx, params.Queries, params.TargetDeviceSerial); inProgress != nil {
		return StartSnapshotBackupResult{}, inProgress
	}

	// Find the target device's namespace. The internal drive cannot be one.
	if params.TargetDeviceSerial == "" {
		return StartSnapshotBackupResult{}, ErrTargetNotManaged
	}
	target, err := fileutil.FilesVFS(params.Registry, params.TargetDeviceSerial)
	if err != nil {
		return StartSnapshotBackupResult{}, ErrTargetNotManaged
	}

	staged, err := stageVaultExportTo(params, target)
	if err != nil {
		return StartSnapshotBackupResult{}, err
	}

	queued, err := params.Queue.Enqueue(ctx, jobutil.EnqueueParams{
		Kind:   Kind,
		Name:   "Snapshot backup",
		Params: JobParams{TargetDeviceSerial: params.TargetDeviceSerial, VaultExport: staged},
		UserID: params.UserID,
	})
	if err != nil {
		if staged != "" {
			discardVaultExport(ctx, staged, target)
		}
		if sqlutil.IsUniqueConstraintErr(err) {
			if inProgress := activeBackup(ctx, params.Queries, params.TargetDeviceSerial); inProgress != nil {
				return StartSnapshotBackupResult{}, inProgress
			}
		}
		return StartSnapshotBackupResult{}, fmt.Errorf("failed to create job: %w", err)
	}

	return StartSnapshotBackupResult{JobID: strconv.FormatInt(queued.Job.ID, 10)}, nil
}

// activeBackup is the error naming the pending or running backup for a target,
// or nil when it has none.
func activeBackup(ctx context.Context, queries *db.Queries, targetSerial string) *BackupInProgressError {
	row, err := queries.GetActiveBackupJob(ctx, targetSerial)
	if err != nil {
		return nil
	}
	return &BackupInProgressError{JobID: strconv.FormatInt(row.ID, 10)}
}

// stageVaultExportTo builds the vault export the request asked for on the
// target and returns its temp name, or "" when it asked for none.
func stageVaultExportTo(params StartSnapshotBackupParams, target vfs.VFS) (string, error) {
	vaultParams, err := prepareVaultExport(params)
	if err != nil || vaultParams == nil {
		return "", err
	}
	defer vaultcrypto.ZeroKey(vaultParams.LiveKey)

	dir, err := hostDir(params.Ctx, target)
	if err != nil {
		return "", err
	}
	removeStaleStagedVaults(dir)
	staged, err := stageVaultExport(params.Ctx, vaultParams.Queries, vaultParams.LiveKey, vaultParams.RecoveryPassword, dir)
	if err != nil {
		return "", fmt.Errorf("vault export: %w", err)
	}
	return staged, nil
}

// prepareVaultExport derives the live vault key the export will be re-encrypted
// from, after checking the credentials that unlock it. It returns nil when the
// request asked for no vault export.
func prepareVaultExport(params StartSnapshotBackupParams) (*VaultExportParams, error) {
	if params.RecoveryPassword == "" {
		return nil, nil
	}
	if params.Username == "" || params.Password == "" {
		return nil, ErrVaultCredentialsRequired
	}
	if len(params.RecoveryPassword) < 8 {
		return nil, ErrRecoveryPasswordTooShort
	}

	ctx := params.Ctx
	if _, _, err := authutil.ValidateBasicAuth(ctx, params.Queries, params.Username, params.Password); err != nil {
		// A raw password goes back as it is: it carries its own 426.
		if errors.Is(err, authutil.ErrAppTooOld) {
			return nil, err
		}
		return nil, ErrInvalidCredentials
	}

	config, err := params.Queries.GetVaultConfig(ctx)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrVaultNotInitialized
	}
	if err != nil {
		return nil, fmt.Errorf("get vault config: %w", err)
	}

	argon2Params := vaultcrypto.Argon2Params{
		Memory:      uint32(config.Argon2Memory),
		Iterations:  uint32(config.Argon2Iterations),
		Parallelism: uint8(config.Argon2Parallelism),
	}
	liveKey := vaultcrypto.DeriveKey(params.Password, config.Salt, argon2Params)

	if !vaultcrypto.CheckVerificationBlob(liveKey, config.VerificationBlob, config.VerificationNonce) {
		vaultcrypto.ZeroKey(liveKey)
		return nil, ErrMasterPasswordMismatch
	}

	return &VaultExportParams{
		Queries:          params.Queries,
		LiveKey:          liveKey,
		RecoveryPassword: params.RecoveryPassword,
	}, nil
}

// gatherSourceDevices lists every managed device the backup should copy from —
// which is all of them but the one being copied onto. A device with no files
// namespace has been unplugged since it was listed, and is left out.
func gatherSourceDevices(storage *storageutil.StorageService, registry vfs.Registry, targetSerial string) ([]SourceDevice, error) {
	managed, err := storage.GetManagedDevices()
	if err != nil {
		return nil, err
	}

	var sources []SourceDevice
	for _, d := range managed {
		serial := ""
		name := d.Name
		if d.UsbInfo != nil {
			serial = d.UsbInfo.GetSerial()
		}
		if serial == targetSerial {
			continue
		}
		files, err := fileutil.FilesVFS(registry, serial)
		if err != nil {
			log.Printf("snapshot backup: skipping %s: %v", name, err)
			continue
		}
		sources = append(sources, SourceDevice{
			Name:   name,
			Serial: serial,
			Files:  files,
		})
	}
	return sources, nil
}
