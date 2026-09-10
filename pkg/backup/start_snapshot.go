package backup

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"

	"github.com/google/uuid"
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
	// Ctx bounds the checks made before the job is created. The backup itself
	// deliberately does not use it: it outlives the request.
	Ctx context.Context
	// Queries reads the device roles and the vault config.
	Queries *db.Queries
	// Storage resolves the target device and the sources to copy from.
	Storage *storageutil.StorageService
	// Store holds the job while it runs.
	Store BackupJobStore
	// EventBus carries progress to anyone watching.
	EventBus *eventbus.Bus
	// IOSemaphore throttles file copies to yield to interactive requests.
	IOSemaphore *iosemutil.Semaphore
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

// StartSnapshotBackupResult reports the job that was started. The backup is
// still running when this returns; poll the store for its progress.
type StartSnapshotBackupResult struct {
	JobID string
}

// StartSnapshotBackup validates the request, creates the job, and runs the
// backup in the background.
func StartSnapshotBackup(params StartSnapshotBackupParams) (StartSnapshotBackupResult, error) {
	ctx := params.Ctx

	role, err := params.Queries.GetDeviceRole(ctx, params.TargetDeviceSerial)
	if err != nil || role != "snapshot-backup" {
		return StartSnapshotBackupResult{}, ErrTargetRoleRequired
	}

	// Check no backup is already running for this target.
	jobs, _ := params.Store.List(ctx)
	for _, j := range jobs {
		if j.TargetDeviceSerial == params.TargetDeviceSerial &&
			(j.Status == BackupStatusPending ||
				j.Status == BackupStatusScanning ||
				j.Status == BackupStatusCopying) {
			return StartSnapshotBackupResult{}, &BackupInProgressError{JobID: j.ID}
		}
	}

	// Find the target managed device.
	targetDev, err := params.Storage.FindManagedDeviceBySerial(params.TargetDeviceSerial)
	if err != nil || targetDev == nil {
		return StartSnapshotBackupResult{}, ErrTargetNotManaged
	}

	// Gather all source devices (everything that isn't the target).
	sources, err := gatherSourceDevices(params.Storage, params.TargetDeviceSerial)
	if err != nil {
		return StartSnapshotBackupResult{}, fmt.Errorf("failed to gather sources: %w", err)
	}

	// If a recovery password is provided, validate credentials and prepare vault export.
	vaultParams, err := prepareVaultExport(params)
	if err != nil {
		return StartSnapshotBackupResult{}, err
	}

	job := &BackupJob{
		ID:                 uuid.New().String(),
		Status:             BackupStatusPending,
		TargetDeviceSerial: params.TargetDeviceSerial,
	}
	if err := params.Store.Create(ctx, job); err != nil {
		return StartSnapshotBackupResult{}, fmt.Errorf("failed to create job: %w", err)
	}

	snapshotParams := SnapshotBackupParams{
		TargetDeviceSerial: params.TargetDeviceSerial,
		Job:                job,
		Store:              params.Store,
		EventBus:           params.EventBus,
		Vault:              vaultParams,
		IOSemaphore:        params.IOSemaphore,
	}
	go func() {
		if vaultParams != nil {
			defer vaultcrypto.ZeroKey(vaultParams.LiveKey)
		}
		if err := SnapshotBackup(context.Background(), snapshotParams, sources, targetDev); err != nil {
			log.Printf("snapshot backup failed: %v", err)
		}
	}()

	return StartSnapshotBackupResult{JobID: job.ID}, nil
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
// which is all of them but the one being copied onto.
func gatherSourceDevices(storage *storageutil.StorageService, targetSerial string) ([]SourceDevice, error) {
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
		sources = append(sources, SourceDevice{
			Name:     name,
			Serial:   serial,
			FilesDir: d.FilesDir,
		})
	}
	return sources, nil
}
