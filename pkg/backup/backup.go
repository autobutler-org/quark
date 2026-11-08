// Package backup snapshots managed-device files, and the chat and vault tables
// as the ciphertext they are, onto a target device, keeps the files in sync as
// they change, and verifies and restores what it wrote.
package backup

import (
	"context"
	"database/sql"
	"sync"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

type BackupJobStatus string

const (
	BackupStatusPending   BackupJobStatus = "PENDING"
	BackupStatusScanning  BackupJobStatus = "SCANNING"
	BackupStatusCopying   BackupJobStatus = "COPYING"
	BackupStatusCompleted BackupJobStatus = "COMPLETED"
	BackupStatusFailed    BackupJobStatus = "FAILED"
)

// SourceDevice is one managed device a snapshot copies from.
type SourceDevice struct {
	Name   string
	Serial string
	// Files is the device's files namespace.
	Files vfs.VFS
}

type SourceDeviceProgress struct {
	DeviceSerial string `json:"deviceSerial"`
	DeviceName   string `json:"deviceName"`
	FilesTotal   int    `json:"filesTotal"`
	FilesCopied  int    `json:"filesCopied"`
	FilesSkipped int    `json:"filesSkipped"`
	BytesTotal   int64  `json:"bytesTotal"`
	BytesCopied  int64  `json:"bytesCopied"`
}

type BackupJob struct {
	ID                 string                 `json:"id"`
	Status             BackupJobStatus        `json:"status"`
	TargetDeviceSerial string                 `json:"targetDeviceSerial"`
	Progress           float64                `json:"progress"`
	TotalFiles         int                    `json:"totalFiles"`
	FilesCopied        int                    `json:"filesCopied"`
	FilesSkipped       int                    `json:"filesSkipped"`
	TotalBytes         int64                  `json:"totalBytes"`
	BytesCopied        int64                  `json:"bytesCopied"`
	SourceDevices      []SourceDeviceProgress `json:"sourceDevices"`
	ErrorMsg           string                 `json:"errorMsg,omitempty"`
	CreatedAt          time.Time              `json:"createdAt"`
	UpdatedAt          time.Time              `json:"updatedAt"`
	CompletedAt        *time.Time             `json:"completedAt,omitempty"`

	// TargetName is what the app calls the drive backed up onto.
	TargetName string `json:"targetName,omitempty"`
	// SourceNames is what the app calls each drive copied, in the order
	// they are copied. It is set when the backup starts scanning.
	SourceNames []string `json:"sourceNames,omitempty"`
	// CurrentSource is the name of the drive being copied now. Empty before
	// copying starts and after the backup completes.
	CurrentSource string `json:"currentSource,omitempty"`
}

type BackupProgressData struct {
	JobID       string  `json:"jobId"`
	Progress    float64 `json:"progress"`
	FilesCopied int     `json:"filesCopied"`
	TotalFiles  int     `json:"totalFiles"`
	BytesCopied int64   `json:"bytesCopied"`
	TotalBytes  int64   `json:"totalBytes"`
	CurrentFile string  `json:"currentFile,omitempty"`
}

// Manifest is backup_manifest.json, at the root of each run. Files' paths are
// relative to the run's folder. CompletedAt and Drives come before Files in
// the JSON, so [ListRuns] reads them without decoding the file list.
type Manifest struct {
	CreatedAt time.Time `json:"createdAt"`
	// CompletedAt is when the run completed.
	CompletedAt time.Time `json:"completedAt"`
	// Drives is the source drive behind each drive folder in the run. A
	// restore finds a folder's drive here, never from the folder's name.
	Drives     []ManifestDrive         `json:"drives"`
	TotalFiles int                     `json:"totalFiles"`
	TotalBytes int64                   `json:"totalBytes"`
	Files      map[string]ManifestFile `json:"files"`
}

// ManifestDrive is one source drive's folder in a run.
type ManifestDrive struct {
	// Folder is the folder's name in the run: "Built-in storage", or the
	// drive's name and the first 8 characters of its serial, as
	// "Photos (USB 90C82C65)".
	Folder string `json:"folder"`
	// Serial is the source drive's serial, "" for built-in storage.
	Serial string `json:"serial"`
	// Name is the source drive's name when the run was taken.
	Name string `json:"name"`
}

// Run is one complete snapshot run: a folder under backups/ on the backup
// drive holding a copy of every source drive, the chat and vault exports, and
// the manifest. [ListRuns] lists them.
type Run struct {
	// Folder is the run's folder under backups/, named after the minute it
	// started in the Quark's local time ("2026-11-07 21.57"), with " (2)"
	// and so on after it when two runs started in the same minute.
	Folder string `json:"folder"`
	// CompletedAt is when the run completed, from its manifest.
	CompletedAt time.Time `json:"completedAt"`
	// Drives is what the run holds, one folder per source drive.
	Drives []ManifestDrive `json:"drives"`
	// SizeBytes is the bytes the run's files hold, its manifest's
	// totalBytes. A file hard-linked from another run counts in both, so
	// deleting a run frees less than this.
	SizeBytes int64 `json:"sizeBytes"`
}

// RunCopy is one data drive a backup drive holds a copy of: the newest
// complete run on that drive whose manifest names the data drive.
type RunCopy struct {
	// Serial is the data drive's serial, "" for built-in storage.
	Serial string `json:"serial"`
	// Name is the data drive's name when that run was taken.
	Name string `json:"name"`
	// CompletedAt is when that run completed.
	CompletedAt time.Time `json:"completedAt"`
}

type ManifestFile struct {
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

type VerifyResult struct {
	// Run is the run that was verified, a folder under backups/.
	Run       string   `json:"run"`
	OK        int      `json:"ok"`
	Missing   []string `json:"missing,omitempty"`
	Corrupted []string `json:"corrupted,omitempty"`
	Added     []string `json:"added,omitempty"`
	Errors    []string `json:"errors,omitempty"`
}

// VaultImportResult reports what [ImportVault] restored.
type VaultImportResult struct {
	// Accounts is how many accounts got their vault key back.
	Accounts int `json:"accounts"`
	Items    int `json:"items"`
	// UnmatchedUsers is the usernames in the backup with no account on this
	// Quark, sorted. None of them had a vault: a backup vault with no account
	// to go to refuses the restore ([ErrVaultAccountMissing]).
	UnmatchedUsers []string `json:"unmatchedUsers"`
	// BackupPasswordAccounts is the restored accounts, sorted, whose vault
	// was wrapped over a salt other than the account's own on this Quark, as
	// every vault restored onto new hardware is (#3614). Such a vault opens
	// with the password the account had when the backup was taken, whatever
	// it signs in with here, and the recovery phrase it had then does not
	// recover it, since this Quark checks the account's own phrase.
	BackupPasswordAccounts []string `json:"backupPasswordAccounts"`
	// RestoredAccounts is the usernames, sorted, of every account here that
	// got a vault back.
	RestoredAccounts []string `json:"restoredAccounts"`
	// RestoredUserIDs is RestoredAccounts' user ids, in the same order, for
	// the caller to publish vault_changed to. Not part of the answer.
	RestoredUserIDs []int64 `json:"-"`
	// Run is the run [RestoreVault] read the vault from, a folder under
	// backups/. [ImportVault] leaves it empty.
	Run string `json:"run,omitempty"`
}

// RestoreVaultParams asks for the vault backup a snapshot wrote to a drive.
type RestoreVaultParams struct {
	Ctx context.Context
	// LiveDB is the live database the vaults are restored into.
	LiveDB *sql.DB
	// Queries reads the drive's role, which must be snapshot-backup.
	Queries db.Querier
	// Registry holds the backup drive's files namespace.
	Registry     vfs.Registry
	DeviceSerial string
	// Run is the run to restore from, a folder under backups/. Empty is the
	// newest complete run.
	Run string
}

// ChatImportResult reports what [ImportChat] restored.
type ChatImportResult struct {
	Channels int `json:"channels"`
	Messages int `json:"messages"`
	// UnmatchedUsers is the usernames in the backup with no account on this
	// Quark, sorted. Their messages read as a deleted account's, and their
	// memberships, reactions and chat keys were not restored.
	UnmatchedUsers []string `json:"unmatchedUsers"`
}

type SnapshotBackupParams struct {
	TargetDeviceSerial string
	Job                *BackupJob
	// Save is called with Job each time its status or progress changes. Nil
	// saves nothing.
	Save     func(job *BackupJob)
	EventBus *eventbus.Bus
	// LiveDB is the live database whose chat and vault tables are exported
	// beside the files, as ciphertext. Nil, or a PostgreSQL database, skips
	// both exports.
	LiveDB      *sql.DB
	IOSemaphore *iosemutil.Semaphore // throttles file copies to yield to interactive requests
	// Queries holds the target's run cache, rewritten after a prune and
	// when the run completes, and the restore jobs a prune keeps clear of.
	// Nil does neither.
	Queries db.Querier
}

type SyncWorker struct {
	mu       sync.Mutex
	bus      *eventbus.Bus
	registry vfs.Registry
	queries  db.Querier
	unsub    func()
	cancel   context.CancelFunc
	running  bool
	pending  []eventbus.Event
	maxQueue int
	ioSem    *iosemutil.Semaphore // throttles file copies to yield to interactive requests

	// targetSerial names the drive to mirror onto. Overridable for testing.
	targetSerial func(ctx context.Context) (serial string, ok bool, err error)
}

type SyncWorkerParams struct {
	Bus *eventbus.Bus
	// Registry holds the internal drive's files namespace and the
	// default-storage drive's, the two live sync copies between.
	Registry    vfs.Registry
	Queries     db.Querier
	IOSemaphore *iosemutil.Semaphore // optional; throttles background file copies
}

func NewSyncWorker(params SyncWorkerParams) *SyncWorker {
	w := &SyncWorker{
		bus:      params.Bus,
		registry: params.Registry,
		queries:  params.Queries,
		maxQueue: 10000,
		ioSem:    params.IOSemaphore,
	}
	w.targetSerial = w.defaultTargetSerial
	return w
}
