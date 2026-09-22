// Package deputil carries the server's dependency graph: the Dependencies
// interface every layer is handed, and the constructors that build it either
// empty (for tests) or wired to the real database, storage, and VFS.
package deputil

import (
	"fmt"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/downloadutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
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

type Dependencies interface {
	AuthRateLimiter() *ratelimitutil.Limiter
	BackupJobStore() backup.BackupJobStore
	Database() *db.DatabaseSqlc
	DownloadTokens() *downloadutil.TokenStore
	EventBus() *eventbus.Bus
	FileIndex() *storageutil.FileIndex
	HealthDatabase() *db.DatabaseRaw
	IOSemaphore() *iosemutil.Semaphore
	JobQueue() *jobutil.Queue
	RepairSystem() repairutil.System
	SSHSystem() sshutil.System
	StorageService() *storageutil.StorageService
	UploadSessions() *uploadutil.SessionStore
	VaultDB() *db.DatabaseSqlc
	VaultRateLimiter() *ratelimitutil.Limiter
	VaultSession() *vaultcrypto.VaultSession
	Worker() workerutil.Worker
	WithDatabase(database *db.DatabaseSqlc) Dependencies
	WithDownloadTokens(store *downloadutil.TokenStore) Dependencies
	WithEventBus(b *eventbus.Bus) Dependencies
	WithFileIndex(idx *storageutil.FileIndex) Dependencies
	WithHealthDatabase(healthDatabase *db.DatabaseRaw) Dependencies
	WithIOSemaphore(sem *iosemutil.Semaphore) Dependencies
	WithJobQueue(q *jobutil.Queue) Dependencies
	WithRepairSystem(system repairutil.System) Dependencies
	WithSSHSystem(system sshutil.System) Dependencies
	MetadataStore() vfs.MetadataStore
	VFSRegistry() vfs.Registry
	WithMetadataStore(s vfs.MetadataStore) Dependencies
	WithStorageService(s *storageutil.StorageService) Dependencies
	WithUploadSessions(store *uploadutil.SessionStore) Dependencies
	WithVFSRegistry(r vfs.Registry) Dependencies
	SetVaultDB(database *db.DatabaseSqlc)
	ClearVaultDB()
	WithVaultSession(session *vaultcrypto.VaultSession) Dependencies
	WithWorker(worker workerutil.Worker) Dependencies
}

func NewDependencies() Dependencies {
	// The upload session store is built here rather than in
	// DefaultDependencies so every dependency graph — every test engine
	// included — has a non-nil store. It allocates a map and nothing else:
	// no goroutine, no directory. StartSweeper, called once from server
	// startup, is what gives it a heartbeat (#1629).
	//
	// The backup job store and the two rate limiters are built here for the
	// same reason: they used to be package-level globals in the handler and
	// middleware packages, so every graph — tests included — needs a non-nil
	// one, and the server's single graph keeps them alive process-wide (#1674).
	return &dependencies{
		backupJobStore: backup.NewInMemoryBackupJobStore(),
		uploadSessions: uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{}),
		// downloadTokens is built here for the same reason: a map and nothing
		// else, swept lazily on each issue (#2226).
		downloadTokens: downloadutil.NewTokenStore(downloadutil.NewTokenStoreParams{}),
		// authRateLimiter protects auth endpoints (login, setup, recover) from
		// brute-force attacks. Shared across all requests — 5 req/s per IP, burst 10.
		authRateLimiter: ratelimitutil.New(),
		// vaultRateLimiter protects /vault/unlock from master-password brute-force.
		// Tighter than the general auth limiter: 1 req/2s per IP, burst 5.
		// After exhausting the burst, the steady-state cap is 0.5 req/s (one every 2s).
		// Combined with Argon2id (~300 ms/attempt), sustained guessing is limited to
		// ≈ 30 attempts/minute per IP — well below what any offline attack would need.
		vaultRateLimiter: ratelimitutil.NewWithRate(0.5, 5),
		// sshSystem is the real host. It runs nothing until an admin asks, and
		// reports itself unavailable anywhere but the installed service (#2131).
		sshSystem: sshutil.DefaultSystem(),
		// repairSystem is the real host too: it reports itself unavailable
		// anywhere but the installed service with a current unit (#2121).
		repairSystem: repairutil.DefaultSystem(),
	}
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
		ID:          "files",                            // coverage: ignore
		Description: "Primary vault file store (files)", // coverage: ignore
	}, vfs.NewStorageServiceVFS(svc, "files")) // coverage: ignore
	deps.WithVFSRegistry(registry)                                         // coverage: ignore
	deps.WithMetadataStore(vfs.NewSQLiteMetadataStore(deps.Database().Db)) // coverage: ignore
	deps.WithEventBus(eventbus.New())                                      // coverage: ignore
	deps.WithJobQueue(jobutil.NewQueue(jobutil.NewQueueParams{             // coverage: ignore
		Database: deps.Database(), // coverage: ignore
		EventBus: deps.EventBus(), // coverage: ignore
	})) // coverage: ignore
	deps.WithVaultSession(vaultcrypto.NewVaultSession()) // coverage: ignore
	deps.WithIOSemaphore(iosemutil.New())                // coverage: ignore
	return deps, nil                                     // coverage: ignore - requires database connection
}
