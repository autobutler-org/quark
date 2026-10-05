package deputil

import (
	"sync"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/downloadutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/fileversionutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/repairutil"
	"github.com/autobutler-org/quark/pkg/util/sshutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/workerutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

type dependencies struct {
	accessCache      *accessutil.Cache
	authRateLimiter  *ratelimitutil.Limiter
	background       sync.WaitGroup
	backupJobStore   backup.BackupJobStore
	byTypeCache      *fileutil.ByTypeCache
	chatRateLimiter  *ratelimitutil.Limiter
	loginGuard       *ratelimitutil.LoginGuard
	vaultRateLimiter *ratelimitutil.Limiter

	database       *db.DatabaseSqlc
	downloadTokens *downloadutil.TokenStore
	zipSlots       *downloadutil.ZipSlots
	eventBus       *eventbus.Bus
	fileIndex      *storageutil.FileIndex
	fileVersions   *fileversionutil.Store
	healthDatabase *db.DatabaseRaw
	sshSystem      sshutil.System
	repairSystem   repairutil.System
	ioSemaphore    *iosemutil.Semaphore
	storageService *storageutil.StorageService
	uploadSessions *uploadutil.SessionStore
	vaultDB        *db.DatabaseSqlc
	vaultDBMu      sync.RWMutex
	vaultSession   *vaultcrypto.VaultSession
	vfsRegistry    vfs.Registry
	metadataStore  vfs.MetadataStore
	jobQueue       *jobutil.Queue
	worker         workerutil.Worker
}

func (d *dependencies) JobQueue() *jobutil.Queue {
	return d.jobQueue
}

func (d *dependencies) WithJobQueue(q *jobutil.Queue) Dependencies {
	d.jobQueue = q
	return d
}

func (d *dependencies) SSHSystem() sshutil.System {
	return d.sshSystem
}

func (d *dependencies) WithSSHSystem(system sshutil.System) Dependencies {
	d.sshSystem = system
	return d
}

func (d *dependencies) RepairSystem() repairutil.System {
	return d.repairSystem
}

func (d *dependencies) WithRepairSystem(system repairutil.System) Dependencies {
	d.repairSystem = system
	return d
}

func (d *dependencies) ByTypeCache() *fileutil.ByTypeCache {
	return d.byTypeCache
}

func (d *dependencies) WithByTypeCache(cache *fileutil.ByTypeCache) Dependencies {
	d.byTypeCache = cache
	return d
}

func (d *dependencies) WithDatabase(database *db.DatabaseSqlc) Dependencies {
	d.database = database
	return d
}

func (d *dependencies) WithEventBus(b *eventbus.Bus) Dependencies {
	d.eventBus = b
	return d
}

func (d *dependencies) WithFileIndex(idx *storageutil.FileIndex) Dependencies {
	d.fileIndex = idx
	return d
}

func (d *dependencies) FileVersions() *fileversionutil.Store {
	return d.fileVersions
}

func (d *dependencies) WithFileVersions(store *fileversionutil.Store) Dependencies {
	d.fileVersions = store
	return d
}

func (d *dependencies) WithHealthDatabase(database *db.DatabaseRaw) Dependencies {
	d.healthDatabase = database
	return d
}

func (d *dependencies) WithStorageService(s *storageutil.StorageService) Dependencies {
	d.storageService = s
	return d
}

func (d *dependencies) WithWorker(worker workerutil.Worker) Dependencies {
	d.worker = worker
	return d
}

func (d *dependencies) AuthRateLimiter() *ratelimitutil.Limiter {
	return d.authRateLimiter
}

func (d *dependencies) Background() *sync.WaitGroup {
	return &d.background
}

func (d *dependencies) BackupJobStore() backup.BackupJobStore {
	return d.backupJobStore
}

func (d *dependencies) ChatRateLimiter() *ratelimitutil.Limiter {
	return d.chatRateLimiter
}

func (d *dependencies) WithChatRateLimiter(limiter *ratelimitutil.Limiter) Dependencies {
	d.chatRateLimiter = limiter
	return d
}

func (d *dependencies) LoginGuard() *ratelimitutil.LoginGuard {
	return d.loginGuard
}

func (d *dependencies) WithLoginGuard(guard *ratelimitutil.LoginGuard) Dependencies {
	d.loginGuard = guard
	return d
}

func (d *dependencies) AccessCache() *accessutil.Cache {
	return d.accessCache
}

func (d *dependencies) WithAccessCache(cache *accessutil.Cache) Dependencies {
	d.accessCache = cache
	return d
}

func (d *dependencies) VaultRateLimiter() *ratelimitutil.Limiter {
	return d.vaultRateLimiter
}

func (d *dependencies) Database() *db.DatabaseSqlc {
	return d.database
}

func (d *dependencies) EventBus() *eventbus.Bus {
	return d.eventBus
}

func (d *dependencies) FileIndex() *storageutil.FileIndex {
	return d.fileIndex
}

func (d *dependencies) HealthDatabase() *db.DatabaseRaw {
	return d.healthDatabase
}

func (d *dependencies) IOSemaphore() *iosemutil.Semaphore {
	return d.ioSemaphore
}

func (d *dependencies) WithIOSemaphore(sem *iosemutil.Semaphore) Dependencies {
	d.ioSemaphore = sem
	return d
}

func (d *dependencies) StorageService() *storageutil.StorageService {
	return d.storageService
}

func (d *dependencies) DownloadTokens() *downloadutil.TokenStore {
	return d.downloadTokens
}

func (d *dependencies) WithDownloadTokens(store *downloadutil.TokenStore) Dependencies {
	d.downloadTokens = store
	return d
}

func (d *dependencies) ZipSlots() *downloadutil.ZipSlots {
	return d.zipSlots
}

func (d *dependencies) WithZipSlots(slots *downloadutil.ZipSlots) Dependencies {
	d.zipSlots = slots
	return d
}

func (d *dependencies) UploadSessions() *uploadutil.SessionStore {
	return d.uploadSessions
}

func (d *dependencies) WithUploadSessions(store *uploadutil.SessionStore) Dependencies {
	d.uploadSessions = store
	return d
}

func (d *dependencies) VaultDB() *db.DatabaseSqlc {
	d.vaultDBMu.RLock()
	defer d.vaultDBMu.RUnlock()
	if d.vaultDB != nil {
		return d.vaultDB
	}
	return d.database
}

func (d *dependencies) SetVaultDB(database *db.DatabaseSqlc) {
	d.vaultDBMu.Lock()
	defer d.vaultDBMu.Unlock()
	d.vaultDB = database
}

func (d *dependencies) ClearVaultDB() {
	d.vaultDBMu.Lock()
	defer d.vaultDBMu.Unlock()
	if d.vaultDB != nil {
		d.vaultDB.Db.Close()
		d.vaultDB = nil
	}
}

func (d *dependencies) VaultSession() *vaultcrypto.VaultSession {
	return d.vaultSession
}

func (d *dependencies) WithVaultSession(session *vaultcrypto.VaultSession) Dependencies {
	d.vaultSession = session
	return d
}

func (d *dependencies) MetadataStore() vfs.MetadataStore {
	return d.metadataStore
}

func (d *dependencies) WithMetadataStore(s vfs.MetadataStore) Dependencies {
	d.metadataStore = s
	return d
}

func (d *dependencies) VFSRegistry() vfs.Registry {
	return d.vfsRegistry
}

func (d *dependencies) WithVFSRegistry(r vfs.Registry) Dependencies {
	d.vfsRegistry = r
	return d
}

func (d *dependencies) Worker() workerutil.Worker {
	return d.worker
}
