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

	docs "github.com/autobutler-org/autobutler/docs/swagger"
	"github.com/autobutler-org/autobutler/internal/db"
	"github.com/autobutler-org/autobutler/internal/server/middleware"
	"github.com/autobutler-org/autobutler/pkg/backup"
	"github.com/autobutler-org/autobutler/pkg/util/authutil"
	"github.com/autobutler-org/autobutler/pkg/util/deputil"
	"github.com/autobutler-org/autobutler/pkg/util/eventbus"
	"github.com/autobutler-org/autobutler/pkg/util/favoritesutil"
	"github.com/autobutler-org/autobutler/pkg/util/healthutil"
	"github.com/autobutler-org/autobutler/pkg/util/remoteutil"
	"github.com/autobutler-org/autobutler/pkg/util/serverutil"
	"github.com/autobutler-org/autobutler/pkg/util/settingsutil"
	"github.com/autobutler-org/autobutler/pkg/util/storageutil"
	"github.com/autobutler-org/autobutler/pkg/util/tlsutil"
	"github.com/autobutler-org/autobutler/pkg/util/workerutil"

	"github.com/gin-gonic/gin"
	swaggerfiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

func setupServices(deps deputil.Dependencies) (*backup.SyncWorker, error) {
	if err := storageutil.SetupCirrusDir(); err != nil {
		return nil, fmt.Errorf("failed to setup cirrus directory: %w", err)
	}
	go deps.Worker().Process()
	go deps.Worker().LogErrors()
	if _, err := favoritesutil.EnsureFavoritesAlbum(
		context.Background(),
		deps.Database().Queries,
	); err != nil {
		log.Printf("[server] warning: could not ensure Favorites album: %v", err)
	}

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

	return syncWorker, nil
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

	for range ticker.C {
		devices, err := storageutil.ListUsbDevices(true)
		if err != nil {
			log.Printf("[storage] usbDeviceMonitor: failed to list USB devices: %v", err)
			continue
		}

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

// StartOptions controls optional server startup behaviour.
type StartOptions struct {
	// Insecure disables TLS and serves over plain HTTP.
	// Use only for local development.
	Insecure bool
}

func StartServer(deps deputil.Dependencies, opts StartOptions) error {
	systemCollector, err := healthutil.Register()
	if err != nil {
		return fmt.Errorf("failed to initialize system collector: %w", err)
	}

	deps.WithWorker(workerutil.NewWorker(deps.StorageService()))
	syncWorker, err := setupServices(deps)
	if err != nil {
		return fmt.Errorf("failed to setup services: %w", err)
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

	if enabled, authKey := settingsutil.GetRemoteAccess(); enabled && authKey != "" {
		if err := remoteutil.Start(authKey); err != nil {
			log.Printf("[remote] failed to start: %v", err)
		} else if err := remoteutil.StartProxy(portNum, !opts.Insecure); err != nil {
			log.Printf("[remote] failed to start proxy: %v", err)
		}
	}

	// Graceful shutdown: stop tsnet and telemetry on SIGINT/SIGTERM.
	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
		<-quit
		log.Println("[server] shutting down...")
		syncWorker.Stop()
		remoteutil.Stop()
		os.Exit(0)
	}()

	router := gin.Default()
	// Disable automatic redirects so unmatched routes (e.g. /health, /photos)
	// fall through to the NoRoute SPA handler instead of 301-redirecting to /.
	router.RedirectTrailingSlash = false
	router.RedirectFixedPath = false

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

		// selfSignedFallback returns the self-signed cert for any SNI name.
		selfSignedFallback := func(_ *tls.ClientHelloInfo) (*tls.Certificate, error) {
			return &cert, nil
		}
		tlsCfg := &tls.Config{
			// GetCertificate tries Tailscale (Let's Encrypt *.ts.net) first,
			// then falls back to the local self-signed cert for LAN clients.
			GetCertificate: remoteutil.GetCertificate(selfSignedFallback),
			MinVersion:     tls.VersionTLS13,
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
