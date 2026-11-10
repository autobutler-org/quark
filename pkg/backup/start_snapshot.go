package backup

import (
	"context"
	"errors"
	"fmt"
	"log"
	"slices"
	"strconv"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// The failures a caller of [StartSnapshotBackup] can fix. Anything else it
// returns is the server's fault. The messages are the ones the client already
// reads, so they travel to the response unchanged.
var (
	ErrTargetRoleRequired = errors.New("target device must have the snapshot-backup role")
	ErrTargetNotManaged   = errors.New("target device not found or not managed")
	// ErrSourceNotDataDrive reports a chosen source that is the target,
	// another backup drive, or not attached (#3984).
	ErrSourceNotDataDrive = errors.New("a source must be an attached data drive, not a backup drive")
)

// BackupInProgressError reports a target device that already has a backup
// running. The handler answers it with 409 and names the job holding the lock.
type BackupInProgressError struct {
	JobID string
}

func (e *BackupInProgressError) Error() string {
	return fmt.Sprintf("backup already running for this device (job %s)", e.JobID)
}

// StartSnapshotBackupParams starts a snapshot backup onto a target device. It
// asks for no password: the chat and vault tables travel as the ciphertext
// they already are (#3460).
type StartSnapshotBackupParams struct {
	// Ctx bounds the checks made before the job is queued. The backup itself
	// runs on the job queue and outlives it.
	Ctx context.Context
	// Queries reads the device roles and the job holding the target's lock.
	Queries db.Querier
	// Registry holds the target device's files namespace.
	Registry vfs.Registry
	// Queue runs the backup. Its Handler for [Kind] comes from [NewHandler].
	Queue *jobutil.Queue
	// UserID is the account starting the backup. 0 records none.
	UserID int64
	// TargetDeviceSerial is the device to back up onto. It must already hold
	// the snapshot-backup role. An empty serial is the internal drive.
	TargetDeviceSerial string
	// SourceSerials are the data drives to copy; empty is every data drive.
	// The serial "" is built-in storage. Each must be attached and must not be
	// the target or another backup drive, or the start fails with
	// [ErrSourceNotDataDrive].
	SourceSerials []string
	// Storage names the drives in the job name. Nil names them by serial.
	Storage *storageutil.StorageService
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
func StartSnapshotBackup(params StartSnapshotBackupParams) (StartSnapshotBackupResult, error) {
	ctx := params.Ctx

	role, err := params.Queries.GetDeviceRole(ctx, params.TargetDeviceSerial)
	if err != nil || role != "snapshot-backup" {
		return StartSnapshotBackupResult{}, ErrTargetRoleRequired
	}

	// The index is the lock. This only answers a request that is going to
	// lose to it with the job it lost to, before any work.
	if inProgress := activeBackup(ctx, params.Queries, params.TargetDeviceSerial); inProgress != nil {
		return StartSnapshotBackupResult{}, inProgress
	}

	// An empty serial is the internal drive. FilesVFS resolves it, and a
	// registry without that namespace is not a managed target.
	if _, err := fileutil.FilesVFS(params.Registry, params.TargetDeviceSerial); err != nil {
		return StartSnapshotBackupResult{}, ErrTargetNotManaged
	}

	backups, err := backupSerials(ctx, params.Queries)
	if err != nil {
		return StartSnapshotBackupResult{}, err
	}
	names := driveNames(params.Storage)
	sources := slices.Compact(slices.Sorted(slices.Values(params.SourceSerials)))
	for _, serial := range sources {
		_, err := fileutil.FilesVFS(params.Registry, serial)
		if serial == params.TargetDeviceSerial || backups[serial] || err != nil {
			return StartSnapshotBackupResult{}, fmt.Errorf("%s: %w", driveName(names, serial), ErrSourceNotDataDrive)
		}
	}
	queued, err := params.Queue.Enqueue(ctx, jobutil.EnqueueParams{
		Kind:   Kind,
		Name:   backupJobName(names, backups, params.TargetDeviceSerial, sources),
		Params: JobParams{TargetDeviceSerial: params.TargetDeviceSerial, SourceSerials: sources},
		UserID: params.UserID,
	})
	if err != nil {
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
func activeBackup(ctx context.Context, queries db.Querier, targetSerial string) *BackupInProgressError {
	row, err := queries.GetActiveBackupJob(ctx, targetSerial)
	if err != nil {
		return nil
	}
	return &BackupInProgressError{JobID: strconv.FormatInt(row.ID, 10)}
}

// backupSerials is the set of drives holding the snapshot-backup role.
func backupSerials(ctx context.Context, queries db.Querier) (map[string]bool, error) {
	roles, err := queries.GetAllDeviceRoles(ctx)
	if err != nil {
		return nil, fmt.Errorf("list device roles: %w", err)
	}
	backups := make(map[string]bool)
	for _, role := range roles {
		if role.Role == "snapshot-backup" {
			backups[role.DeviceSerial] = true
		}
	}
	return backups, nil
}

// gatherSourceDevices lists every managed device the backup should copy from:
// the data drives, every one but the target and the other backup drives
// (#4037), and of those only the chosen serials when any are (#3984). A
// device with no files namespace has been unplugged since it was listed, and
// is left out.
func gatherSourceDevices(storage *storageutil.StorageService, registry vfs.Registry, backups map[string]bool, targetSerial string, chosen []string) ([]SourceDevice, error) {
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
		// The target is skipped by serial too: its role may have changed since
		// the job was queued, and a drive is never copied onto itself.
		if serial == targetSerial || backups[serial] || (len(chosen) > 0 && !slices.Contains(chosen, serial)) {
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
