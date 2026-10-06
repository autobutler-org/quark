// Package backup snapshots the vault and managed-device files onto a target
// device, keeps them in sync as files change, and verifies restores.
package backup

import (
	"context"
	"sync"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

type BackupJobStatus string

const (
	BackupStatusPending   BackupJobStatus = "PENDING"
	BackupStatusScanning  BackupJobStatus = "SCANNING"
	BackupStatusCopying   BackupJobStatus = "COPYING"
	BackupStatusCompleted BackupJobStatus = "COMPLETED"
	BackupStatusFailed    BackupJobStatus = "FAILED"
)

type SourceDevice struct {
	Name     string
	Serial   string
	FilesDir string
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

type SnapshotBackupParams struct {
	TargetDeviceSerial string
	Job                *BackupJob
	Store              BackupJobStore
	EventBus           *eventbus.Bus
	Vault              *VaultExportParams
	IOSemaphore        *iosemutil.Semaphore // throttles file copies to yield to interactive requests
}

type SyncWorker struct {
	mu       sync.Mutex
	bus      *eventbus.Bus
	storage  *storageutil.StorageService
	queries  *db.Queries
	unsub    func()
	cancel   context.CancelFunc
	running  bool
	pending  []eventbus.Event
	maxQueue int
	ioSem    *iosemutil.Semaphore // throttles file copies to yield to interactive requests

	// Overridable for testing.
	resolveTarget      func(ctx context.Context) (string, error)
	resolveInternalDir func() (string, error)
}

type SyncWorkerParams struct {
	Bus         *eventbus.Bus
	Storage     *storageutil.StorageService
	Queries     *db.Queries
	IOSemaphore *iosemutil.Semaphore // optional; throttles background file copies
}

func NewSyncWorker(params SyncWorkerParams) *SyncWorker {
	w := &SyncWorker{
		bus:      params.Bus,
		storage:  params.Storage,
		queries:  params.Queries,
		maxQueue: 10000,
		ioSem:    params.IOSemaphore,
	}
	w.resolveTarget = w.defaultResolveTarget
	w.resolveInternalDir = w.defaultResolveInternalDir
	return w
}
