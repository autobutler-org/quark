package backup

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strconv"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// Kind is the jobutil kind snapshot backups are stored and registered under.
// The jobs table's per-target lock, idx_jobs_backup_target, spells it too.
const Kind = "snapshot-backup"

// detailInterval is how often a running backup saves its counts to its row.
// A change of phase is always saved.
const detailInterval = time.Second

// ErrBackupJobNotFound is returned for an id that is not a snapshot backup's.
var ErrBackupJobNotFound = errors.New("backup job not found")

// JobParams is what a snapshot backup job stores. The API hands a job's
// params to any signed-in client, so nothing secret goes here: the vault
// export is built by the request that starts the backup, and the job only
// carries the name of the file it left on the target.
type JobParams struct {
	// TargetDeviceSerial is the device backed up onto. The per-target lock
	// reads it out of the stored params.
	TargetDeviceSerial string `json:"targetDeviceSerial"`
	// VaultExport is the staged vault export's file name on the target. Empty
	// means the backup carries no vault export.
	VaultExport string `json:"vaultExport,omitempty"`
}

// NewHandlerParams configures NewHandler.
type NewHandlerParams struct {
	// Database holds the job rows a running backup saves its counts to, and
	// the chat tables it exports.
	Database *db.DatabaseSqlc
	// Storage lists the managed devices to copy from.
	Storage *storageutil.StorageService
	// Registry holds every attached device's files namespace, the target's
	// and the sources'.
	Registry vfs.Registry
	// EventBus carries the backup_* events. Nil publishes nothing.
	EventBus *eventbus.Bus
	// IOSemaphore throttles file copies to yield to interactive requests.
	IOSemaphore *iosemutil.Semaphore
	// DataDir is the Quark's data directory, where a completed snapshot is
	// recorded. Empty records nothing.
	DataDir string
}

// NewHandler returns the jobutil Handler for Kind. Run looks the target and
// the sources up again, so it sees what is attached to the instance running
// it, copies every source onto the target, and saves its phase and counts to
// the job row as it goes, where [GetSnapshotBackupStatus] reads them from any
// instance. A staged vault export is removed when the run ends, however it
// ends, so Validate refuses to retry a backup that had one.
//
// ponytail: one lane, so an instance runs one backup at a time and a second
// target's backup waits behind the first. Give it a lane per target if two
// backup drives ever need to fill at once.
func NewHandler(params NewHandlerParams) jobutil.Handler {
	return jobutil.Handler{
		Run: func(ctx context.Context, raw json.RawMessage, report func(float64)) error {
			return runSnapshotJob(ctx, params, raw, report)
		},
		Validate: func(raw json.RawMessage) error {
			var job JobParams
			if err := json.Unmarshal(raw, &job); err != nil {
				return fmt.Errorf("decode backup params: %w", err)
			}
			if job.VaultExport != "" {
				return errors.New("a backup with a vault export cannot be retried; start a new backup")
			}
			return nil
		},
	}
}

func runSnapshotJob(ctx context.Context, params NewHandlerParams, raw json.RawMessage, report func(float64)) error {
	var jobParams JobParams
	if err := json.Unmarshal(raw, &jobParams); err != nil {
		return fmt.Errorf("decode backup params: %w", err)
	}
	if jobParams.TargetDeviceSerial == "" {
		return ErrTargetNotManaged
	}
	target, err := fileutil.FilesVFS(params.Registry, jobParams.TargetDeviceSerial)
	if err != nil {
		return ErrTargetNotManaged
	}
	if jobParams.VaultExport != "" {
		defer discardVaultExport(context.WithoutCancel(ctx), jobParams.VaultExport, target)
	}
	sources, err := gatherSourceDevices(params.Storage, params.Registry, jobParams.TargetDeviceSerial)
	if err != nil {
		return fmt.Errorf("failed to gather sources: %w", err)
	}

	id := jobutil.JobID(ctx)
	var savedStatus BackupJobStatus
	var savedAt time.Time
	save := func(job *BackupJob) {
		report(job.Progress)
		if job.Status == savedStatus && time.Since(savedAt) < detailInterval {
			return
		}
		savedStatus, savedAt = job.Status, time.Now()
		detail, err := json.Marshal(job)
		if err == nil {
			// A canceled job still records the counts it stopped at.
			err = params.Database.Queries.UpdateJobDetail(context.WithoutCancel(ctx), db.UpdateJobDetailParams{
				Detail: string(detail),
				ID:     id,
			})
		}
		if err != nil {
			// A failed save must not abort the backup.
			log.Printf("snapshot backup: save progress of job %d: %v", id, err)
		}
	}

	return SnapshotBackup(ctx, SnapshotBackupParams{
		TargetDeviceSerial: jobParams.TargetDeviceSerial,
		Job: &BackupJob{
			ID:                 strconv.FormatInt(id, 10),
			Status:             BackupStatusPending,
			TargetDeviceSerial: jobParams.TargetDeviceSerial,
		},
		Save:        save,
		EventBus:    params.EventBus,
		VaultExport: jobParams.VaultExport,
		ChatDB:      params.Database.Db,
		IOSemaphore: params.IOSemaphore,
		DataDir:     params.DataDir,
	}, sources, target)
}

// GetSnapshotBackupStatusParams names the backup job to read.
type GetSnapshotBackupStatusParams struct {
	Ctx     context.Context
	Queries *db.Queries
	// JobID is the id [StartSnapshotBackup] returned.
	JobID string
}

// GetSnapshotBackupStatusResult carries the job as the storage page reads it.
type GetSnapshotBackupStatusResult struct {
	Job BackupJob
}

// GetSnapshotBackupStatus reads a backup's status from its job row, so any
// instance answers for a backup another one is running, and a backup cut off
// by a restart reads as failed. It returns ErrBackupJobNotFound for an id that
// is not a snapshot backup's.
func GetSnapshotBackupStatus(params GetSnapshotBackupStatusParams) (GetSnapshotBackupStatusResult, error) {
	id, err := strconv.ParseInt(params.JobID, 10, 64)
	if err != nil {
		return GetSnapshotBackupStatusResult{}, ErrBackupJobNotFound
	}
	row, err := params.Queries.GetJob(params.Ctx, id)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && row.Kind != Kind) {
		return GetSnapshotBackupStatusResult{}, ErrBackupJobNotFound
	}
	if err != nil {
		return GetSnapshotBackupStatusResult{}, fmt.Errorf("get backup job: %w", err)
	}

	// The detail is the job as the run last saved it. The row is the truth
	// about where the job stands, so it overrides everything it also holds.
	var job BackupJob
	_ = json.Unmarshal([]byte(row.Detail), &job) // "{}" before the first save
	var jobParams JobParams
	_ = json.Unmarshal([]byte(row.Params), &jobParams)
	phase := job.Status

	job.ID = params.JobID
	job.TargetDeviceSerial = jobParams.TargetDeviceSerial
	job.Progress = row.Progress
	job.ErrorMsg = ""
	job.CreatedAt = row.CreatedAt
	job.UpdatedAt = row.CreatedAt
	if row.StartedAt.Valid {
		job.UpdatedAt = row.StartedAt.Time
	}
	job.CompletedAt = nil
	if row.FinishedAt.Valid {
		job.UpdatedAt = row.FinishedAt.Time
		job.CompletedAt = &row.FinishedAt.Time
	}
	switch jobutil.Status(row.Status) {
	case jobutil.StatusPending:
		job.Status = BackupStatusPending
	case jobutil.StatusRunning:
		job.Status = BackupStatusCopying
		if phase == "" || phase == BackupStatusPending || phase == BackupStatusScanning {
			job.Status = BackupStatusScanning
		}
	case jobutil.StatusCompleted:
		job.Status = BackupStatusCompleted
	case jobutil.StatusCanceled:
		job.Status = BackupStatusFailed
		job.ErrorMsg = "canceled"
	default:
		job.Status = BackupStatusFailed
		job.ErrorMsg = row.Error
	}
	return GetSnapshotBackupStatusResult{Job: job}, nil
}
