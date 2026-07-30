package deputil

import (
	"fmt"
	"sync"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/pluginutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/workerutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

type Dependencies interface {
	Database() *db.DatabaseSqlc
	EventBus() *eventbus.Bus
	FileIndex() *storageutil.FileIndex
	HealthDatabase() *db.DatabaseRaw
	IOSemaphore() *iosemutil.Semaphore
	StorageService() *storageutil.StorageService
	VaultDB() *db.DatabaseSqlc
	VaultSession() *vaultcrypto.VaultSession
	Worker() workerutil.Worker
	WithDatabase(database *db.DatabaseSqlc) Dependencies
	WithEventBus(b *eventbus.Bus) Dependencies
	WithFileIndex(idx *storageutil.FileIndex) Dependencies
	WithHealthDatabase(healthDatabase *db.DatabaseRaw) Dependencies
	WithIOSemaphore(sem *iosemutil.Semaphore) Dependencies
	MetadataStore() vfs.MetadataStore
	PluginHost() *pluginutil.Host
	VFSRegistry() vfs.Registry
	WithMetadataStore(s vfs.MetadataStore) Dependencies
	WithPluginHost(h *pluginutil.Host) Dependencies
	WithStorageService(s *storageutil.StorageService) Dependencies
	WithVFSRegistry(r vfs.Registry) Dependencies
	SetVaultDB(database *db.DatabaseSqlc)
	ClearVaultDB()
	WithVaultSession(session *vaultcrypto.VaultSession) Dependencies
	WithWorker(worker workerutil.Worker) Dependencies
}

type dependencies struct {
	database       *db.DatabaseSqlc
	eventBus       *eventbus.Bus
	fileIndex      *storageutil.FileIndex
	healthDatabase *db.DatabaseRaw
	ioSemaphore    *iosemutil.Semaphore
	pluginHost     *pluginutil.Host
	storageService *storageutil.StorageService
	vaultDB        *db.DatabaseSqlc
	vaultDBMu      sync.RWMutex
	vaultSession   *vaultcrypto.VaultSession
	vfsRegistry    vfs.Registry
	metadataStore  vfs.MetadataStore
	worker         workerutil.Worker
}

func NewDependencies() Dependencies {
	return &dependencies{}
}

func DefaultDependencies() (Dependencies, error) {
	deps := NewDependencies()                                // coverage: ignore - requires database connection
	if database, err := db.ConnectToDatabase(); err == nil { // coverage: ignore - requires database connection success
		deps.WithDatabase(database)
	} else { // coverage: ignore - requires database connection failure
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}
	if database, err := db.ConnectToHealthDatabase(); err == nil { // coverage: ignore - requires health database connection success
		deps.WithHealthDatabase(database)
	} else { // coverage: ignore - requires health database connection failure
		return nil, fmt.Errorf("failed to connect to health database: %w", err)
	}
	svc := storageutil.NewStorageService(storageutil.NewDetector()) // coverage: ignore
	deps.WithStorageService(svc)                                    // coverage: ignore
	registry := vfs.NewRegistry()                                   // coverage: ignore
	_ = registry.Register(vfs.Namespace{                            // coverage: ignore
		ID:          "files",                             // coverage: ignore
		Description: "Primary vault file store (cirrus)", // coverage: ignore
	}, vfs.NewStorageServiceVFS(svc, "files")) // coverage: ignore
	deps.WithVFSRegistry(registry)                                         // coverage: ignore
	deps.WithMetadataStore(vfs.NewSQLiteMetadataStore(deps.Database().Db)) // coverage: ignore
	deps.WithEventBus(eventbus.New())                                      // coverage: ignore
	deps.WithVaultSession(vaultcrypto.NewVaultSession())                   // coverage: ignore
	deps.WithIOSemaphore(iosemutil.New())                                  // coverage: ignore
	return deps, nil                                                       // coverage: ignore - requires database connection
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

func (d *dependencies) PluginHost() *pluginutil.Host {
	return d.pluginHost
}

func (d *dependencies) WithPluginHost(h *pluginutil.Host) Dependencies {
	d.pluginHost = h
	return d
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
