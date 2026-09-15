package server

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	docs "github.com/autobutler-org/quark/docs/swagger"
	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/healthutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/provisionutil"
	"github.com/autobutler-org/quark/pkg/util/remoteutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/tlsutil"
	"github.com/autobutler-org/quark/pkg/util/transcodeutil"
	"github.com/autobutler-org/quark/pkg/util/updateutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/util/workerutil"

	"github.com/gin-gonic/gin"
	swaggerfiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

// setupServices starts the background services. The returned func stops the
// job worker and waits for it, so a job interrupted by shutdown cleans up and
// is marked failed before the process exits.
func setupServices(deps deputil.Dependencies) (*backup.SyncWorker, func(), error) {
	if err := storageutil.SetupFilesDir(); err != nil {
		return nil, nil, fmt.Errorf("failed to setup files directory: %w", err)
	}
	go func() {
		if err := deps.Worker().Process(); err != nil {
			log.Printf("[server] worker stopped: %v", err)
		}
	}()
	jobs := deps.JobQueue()
	jobs.Register(jobutil.RegisterParams{
		Kind: transcodeutil.Kind,
		Handler: transcodeutil.NewHandler(transcodeutil.NewHandlerParams{
			Storage:  deps.StorageService(),
			Database: deps.Database(),
			EventBus: deps.EventBus(),
		}),
	})
	jobsCtx, cancelJobs := context.WithCancel(context.Background())
	jobsDone := make(chan struct{})
	go func() {
		defer close(jobsDone)
		jobs.Run(jobsCtx)
	}()
	stopJobs := func() {
		cancelJobs()
		<-jobsDone
	}
	go func() {
		if err := deps.Worker().LogErrors(); err != nil {
			log.Printf("[server] worker error logger stopped: %v", err)
		}
	}()
	syncWorker := backup.NewSyncWorker(backup.SyncWorkerParams{
		Bus:         deps.EventBus(),
		Storage:     deps.StorageService(),
		Queries:     deps.Database().Queries,
		IOSemaphore: deps.IOSemaphore(),
	})
	syncWorker.Start()

	// Build the file index and start watching for changes.
	// All event-dispatch logic lives in FileIndex.BuildAndWatch.
	idx := storageutil.NewFileIndex()
	idx.BuildAndWatch(deps.EventBus(), deps.StorageService().GetManagedDevices)
	deps.WithFileIndex(idx)

	// Start the FTS5 content indexer — indexes uploaded text files and
	// removes entries for deleted/moved files.
	go startContentIndexer(deps)

	// Index files that were already on disk. The event-driven indexer above
	// only sees writes that happen while it is running, so without this pass
	// existing documents are never searchable.
	go backfillContentIndex(deps)

	initExternalVault(deps)
	go vaultDeviceMonitor(deps)
	go usbDeviceMonitor(deps)

	// Purge expired sessions once at startup and then every 24 hours. (#1330)
	// GetSession already filters on expires_at, so stale rows are not a security
	// issue — but they accumulate forever otherwise on a busy instance.
	go func() {
		purge := func() {
			if db := deps.Database(); db != nil {
				ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer cancel()
				if err := authutil.PurgeExpiredSessions(ctx, db.Queries); err != nil {
					log.Printf("[auth] expired session purge failed: %v", err)
				}
			}
		}
		purge() // once at startup
		ticker := time.NewTicker(24 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			purge()
		}
	}()

	// Delete trashed items older than storageutil.TrashRetentionDays, once at
	// startup and then hourly, on every managed device (#1814). The purge
	// publishes trash_changed for each device it touched.
	go func() {
		purge := func() {
			res, err := deps.StorageService().PurgeExpiredTrash(storageutil.PurgeExpiredTrashParams{
				EventBus: deps.EventBus(),
			})
			if err != nil {
				log.Printf("[trash] expired trash purge failed: %v", err)
			}
			// Rows go with what the sweep deleted for good (#1905).
			for _, removed := range res.Removed {
				if _, rowErr := accessutil.DeleteRows(accessutil.DeleteRowsParams{
					Ctx:          context.Background(),
					Database:     deps.Database(),
					EventBus:     deps.EventBus(),
					DeviceSerial: removed.DeviceSerial,
					Paths:        []string{removed.Path},
				}); rowErr != nil {
					log.Printf("[trash] could not delete access rows for %s: %v", removed.Path, rowErr)
				}
			}
			if res.Purged > 0 {
				log.Printf("[trash] purged %d expired item(s)", res.Purged)
			}
		}
		purge()
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			purge()
		}
	}()

	// Give the resumable upload sessions their heartbeat. The store itself is
	// built in deputil.NewDependencies so every dependency graph has one, but
	// only a real server should be running a goroutine over it — an abandoned
	// chunked upload leaks its staged bytes until this sweeps them (#1629).
	if sessions := deps.UploadSessions(); sessions != nil {
		sessions.StartSweeper(context.Background(), uploadutil.DefaultSweepInterval)
	}

	return syncWorker, stopJobs, nil
}

func initExternalVault(deps deputil.Dependencies) {
	serial, err := deps.Database().Queries.GetVaultLocation(context.Background())
	if err != nil || serial == "" {
		return
	}
	device, err := deps.StorageService().FindManagedDeviceBySerial(serial)
	if err != nil || device == nil {
		log.Printf("[vault] external vault device %s not found at startup — vault unavailable until reconnected", serial)
		return
	}
	dbPath := filepath.Join(device.DataDir, "vault.db")
	vaultDB, err := db.ConnectToVaultDatabase(dbPath)
	if err != nil {
		log.Printf("[vault] failed to open external vault db: %v", err)
		return
	}
	deps.SetVaultDB(vaultDB)
	log.Printf("[vault] external vault loaded from device %s", serial)
}

func vaultDeviceMonitor(deps deputil.Dependencies) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	wasConnected := true

	for range ticker.C {
		serial, err := deps.Database().Queries.GetVaultLocation(context.Background())
		if err != nil || serial == "" {
			continue
		}

		device, err := deps.StorageService().FindManagedDeviceBySerial(serial)
		connected := err == nil && device != nil

		if wasConnected && !connected {
			log.Printf("[vault] external device %s disconnected — locking vault", serial)
			deps.VaultSession().LockWithReason("storage device disconnected")
			deps.ClearVaultDB()
			deps.EventBus().Publish(eventbus.Event{
				Kind: eventbus.EventVaultDeviceDisconnected,
				Data: map[string]string{"serial": serial},
			})
			wasConnected = false
		} else if !wasConnected && connected {
			log.Printf("[vault] external device %s reconnected — vault available to unlock", serial)
			dbPath := filepath.Join(device.DataDir, "vault.db")
			vaultDB, err := db.ConnectToVaultDatabase(dbPath)
			if err != nil {
				log.Printf("[vault] failed to reopen vault db: %v", err)
				continue
			}
			deps.SetVaultDB(vaultDB)
			deps.EventBus().Publish(eventbus.Event{
				Kind: eventbus.EventVaultDeviceReconnected,
				Data: map[string]string{"serial": serial},
			})
			wasConnected = true
		}
	}
}

// usbDeviceMonitor polls for newly connected USB storage devices and
// auto-mounts them via storageutil.AutoMountDevice so they are immediately
// operational without manual user intervention.
func usbDeviceMonitor(deps deputil.Dependencies) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	// Track serials we've already handled so we don't reattempt on every tick.
	handled := make(map[string]bool)

	// An enumeration failure is usually permanent, so log it on transition
	// rather than on every 5s tick — otherwise one bad host produces 17k
	// identical lines a day and buries everything else (#1788).
	lastErr := ""

	for range ticker.C {
		devices, err := storageutil.ListUsbDevices(true)
		if err != nil {
			if err.Error() != lastErr {
				lastErr = err.Error()
				log.Printf("[storage] usbDeviceMonitor: failed to list USB devices: %v", err)
			}
			continue
		}
		lastErr = ""

		for _, device := range devices {
			serial := device.GetSerial()
			if serial == "" || handled[serial] {
				continue
			}
			if device.GetMountPath() != "" {
				handled[serial] = true // already mounted — no action needed
				continue
			}

			result, err := storageutil.AutoMountDevice(device)
			if err != nil {
				log.Printf("[storage] usbDeviceMonitor: failed to auto-mount %s: %v", serial, err)
				if result == nil {
					continue // mount itself failed — retry next tick
				}
				// Mount succeeded but data-dir init failed — still mark handled.
			}

			handled[serial] = true
			deps.StorageService().InvalidateDeviceCache()
			deps.EventBus().Publish(eventbus.Event{
				Kind: eventbus.EventVaultStorageChanged,
				Data: map[string]string{"serial": serial},
			})
			log.Printf("[storage] auto-mounted new device %s at %s", serial, result.MountTargetPath)
		}
	}
}

func setupSwagger(router *gin.Engine) {
	docs.SwaggerInfo.BasePath = "/api/v0"
	router.GET("/swagger", func(c *gin.Context) {
		c.Redirect(302, "/swagger/index.html")
	})
	router.GET("/swagger/", func(c *gin.Context) {
		c.Redirect(302, "/swagger/index.html")
	})
	router.GET("/swagger/:any", ginSwagger.WrapHandler(swaggerfiles.Handler))
}

// StartOptions controls optional server startup behavior.
type StartOptions struct {
	// Insecure disables TLS and serves over plain HTTP.
	// Use only for local development.
	Insecure bool
}

// newEngine builds the gin engine every route is mounted on.
func newEngine() (*gin.Engine, error) {
	proxies, err := serverutil.TrustedProxies()
	if err != nil {
		return nil, err
	}
	router := gin.Default()
	// Disable automatic redirects so unmatched routes (e.g. /health, /photos)
	// fall through to the NoRoute SPA handler instead of 301-redirecting to /.
	router.RedirectTrailingSlash = false
	router.RedirectFixedPath = false
	// gin trusts X-Forwarded-For from every peer by default, which lets any
	// client pick the IP the login rate limiter keys on. Believe it only from
	// the configured proxies: loopback, where the tsnet proxy connects from,
	// unless QUARK_TRUSTED_PROXIES says otherwise.
	cidrs := make([]string, 0, len(proxies))
	for _, n := range proxies {
		cidrs = append(cidrs, n.String())
	}
	if err := router.SetTrustedProxies(cidrs); err != nil {
		return nil, fmt.Errorf("QUARK_TRUSTED_PROXIES: %w", err)
	}
	return router, nil
}

func StartServer(deps deputil.Dependencies, opts StartOptions) error {
	if result, err := updateutil.RemoveStaleBackups(updateutil.RemoveStaleBackupsParams{}); err != nil {
		log.Printf("[update] failed to remove stale binary backups: %v", err)
	} else if len(result.Removed) > 0 {
		log.Printf("[update] removed %d stale binary backup(s) from %s", len(result.Removed), os.TempDir())
	}

	systemCollector, err := healthutil.Register()
	if err != nil {
		return fmt.Errorf("failed to initialize system collector: %w", err)
	}

	deps.WithWorker(workerutil.NewWorker(deps.StorageService()))
	syncWorker, stopJobs, err := setupServices(deps)
	if err != nil {
		return fmt.Errorf("failed to setup services: %w", err)
	}

	router, err := newEngine()
	if err != nil {
		return err
	}

	// In TLS mode the server binds to HTTPS_PORT (default 443); in insecure
	// mode it binds to PORT (default 8080). The two env vars are intentionally
	// separate so that in-place upgrades on existing installations do not
	// require a service-file edit.
	var portNum int
	if opts.Insecure {
		portNum = serverutil.ServerPort()
	} else {
		portNum = serverutil.ServerHttpsPort()
	}
	port := fmt.Sprintf("%d", portNum)
	// Record the real bound address so the remote-access proxy (which can also
	// be started later, from the settings API) targets the right port and
	// protocol instead of guessing.
	serverutil.SetServingAddr(portNum, !opts.Insecure)

	// A failure here is recorded by remoteutil and reported by GET
	// /settings/remote-access. The setting stays on: the user asked for remote
	// access, and Settings shows it as on but failing (#1815). The persisted
	// tsnet state is reused; a key is provisioned only when there is none
	// (#1876). In the background, so a slow provisioning service cannot hold
	// up the server's own listener.
	if settingsutil.GetRemoteAccess() {
		go func() {
			if err := remoteutil.EnsureStarted(portNum, !opts.Insecure, func() (string, error) {
				result, err := provisionutil.ProvisionAuthKey(provisionutil.ProvisionAuthKeyParams{})
				return result.AuthKey, err
			}); err != nil {
				log.Printf("[remote] failed to start: %v", err)
			}
		}()
	}

	// Graceful shutdown: stop tsnet and telemetry on SIGINT/SIGTERM.
	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
		<-quit
		log.Println("[server] shutting down...")
		syncWorker.Stop()
		stopJobs()
		remoteutil.Stop()
		os.Exit(0)
	}()

	// IMPORTANT: middleware.Use MUST be called before setupRoutes
	middleware.Use(router, deps)
	if err := setupRoutes(router, systemCollector, deps); err != nil {
		return fmt.Errorf("failed to set up routes: %w", err)
	}
	setupSwagger(router)

	if opts.Insecure {
		log.Println("[server] WARNING: TLS disabled — running in insecure HTTP mode")
		if err := router.Run(fmt.Sprintf(":%s", port)); err != nil {
			return err
		}
	} else {
		dataDir := storageutil.GetDataDir()
		certFile, keyFile, err := tlsutil.EnsureSelfSignedCert(dataDir)
		if err != nil {
			return fmt.Errorf("failed to provision TLS cert: %w", err)
		}

		// Load the cert/key pair and build a TLS config that enforces TLS 1.3
		// as the minimum version. Go 1.22+ automatically negotiates
		// X25519MLKEM768 hybrid PQC key exchange in TLS 1.3 sessions, so no
		// extra configuration is needed for post-quantum hybrid key exchange.
		cert, err := tls.LoadX509KeyPair(certFile, keyFile)
		if err != nil {
			return fmt.Errorf("failed to load TLS key pair: %w", err)
		}
		tlsCfg := &tls.Config{
			Certificates: []tls.Certificate{cert},
			MinVersion:   tls.VersionTLS13,
		}

		addr := fmt.Sprintf(":%s", port)
		ln, err := net.Listen("tcp", addr)
		if err != nil {
			return fmt.Errorf("failed to bind TLS listener on %s: %w", addr, err)
		}
		tlsLn := tls.NewListener(ln, tlsCfg)

		log.Printf("[server] TLS 1.3+ enabled — cert: %s", certFile)
		if err := router.RunListener(tlsLn); err != nil {
			return err
		}
	}

	return nil
}
