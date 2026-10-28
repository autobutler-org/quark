package backup

import (
	"context"
	"errors"
	"fmt"
	"log"
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
	// the snapshot-backup role.
	TargetDeviceSerial string
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

	// Find the target device's namespace. The internal drive cannot be one.
	if params.TargetDeviceSerial == "" {
		return StartSnapshotBackupResult{}, ErrTargetNotManaged
	}
	if _, err := fileutil.FilesVFS(params.Registry, params.TargetDeviceSerial); err != nil {
		return StartSnapshotBackupResult{}, ErrTargetNotManaged
	}

	queued, err := params.Queue.Enqueue(ctx, jobutil.EnqueueParams{
		Kind:   Kind,
		Name:   "Snapshot backup",
		Params: JobParams{TargetDeviceSerial: params.TargetDeviceSerial},
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
