// Package backup snapshots the vault, the chat tables and managed-device files
// onto a target device, keeps the files in sync as they change, and verifies
// and restores what it wrote.
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

type BackupJobStore interface {
	Create(ctx context.Context, job *BackupJob) error
	Get(ctx context.Context, jobID string) (*BackupJob, error)
	Update(ctx context.Context, job *BackupJob) error
	List(ctx context.Context) ([]*BackupJob, error)
}

type InMemoryBackupJobStore struct {
	mu   sync.RWMutex
	jobs map[string]*BackupJob
}

func NewInMemoryBackupJobStore() *InMemoryBackupJobStore {
	return &InMemoryBackupJobStore{jobs: make(map[string]*BackupJob)}
}

type Manifest struct {
	CreatedAt  time.Time               `json:"createdAt"`
	TotalFiles int                     `json:"totalFiles"`
	TotalBytes int64                   `json:"totalBytes"`
	Files      map[string]ManifestFile `json:"files"`
}

type ManifestFile struct {
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

type VerifyResult struct {
	OK        int      `json:"ok"`
	Missing   []string `json:"missing,omitempty"`
	Corrupted []string `json:"corrupted,omitempty"`
	Added     []string `json:"added,omitempty"`
	Errors    []string `json:"errors,omitempty"`
}

type VaultExportParams struct {
	Queries          *db.Queries
	LiveKey          []byte
	RecoveryPassword string
}

type VaultImportResult struct {
	EntriesImported int `json:"entriesImported"`
	EntriesSkipped  int `json:"entriesSkipped"`
	FoldersImported int `json:"foldersImported"`
	FoldersSkipped  int `json:"foldersSkipped"`
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
	Store              BackupJobStore
	EventBus           *eventbus.Bus
	Vault              *VaultExportParams
	// ChatDB is the live database whose chat tables are exported beside the
	// files. Nil skips the chat export.
	ChatDB      *sql.DB
	IOSemaphore *iosemutil.Semaphore // throttles file copies to yield to interactive requests
}

type SyncWorker struct {
	mu       sync.Mutex
	bus      *eventbus.Bus
	registry vfs.Registry
	queries  *db.Queries
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
	Queries     *db.Queries
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
