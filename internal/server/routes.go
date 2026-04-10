package server

import (
	"embed"
	"fmt"
	"log/slog"
	"net/http"

	v1_auth "github.com/autobutler-org/autobutler/internal/server/api/v1/auth"
	v1_books "github.com/autobutler-org/autobutler/internal/server/api/v1/books"
	v1_files "github.com/autobutler-org/autobutler/internal/server/api/v1/cirrus"
	v1_devices "github.com/autobutler-org/autobutler/internal/server/api/v1/devices"
	v1_events "github.com/autobutler-org/autobutler/internal/server/api/v1/events"
	v1_health "github.com/autobutler-org/autobutler/internal/server/api/v1/health"
	v1_metrics "github.com/autobutler-org/autobutler/internal/server/api/v1/metrics"
	v1_migration "github.com/autobutler-org/autobutler/internal/server/api/v1/migration"
	v1_photos "github.com/autobutler-org/autobutler/internal/server/api/v1/photos"
	v1_plugins "github.com/autobutler-org/autobutler/internal/server/api/v1/plugins"
	v1_settings "github.com/autobutler-org/autobutler/internal/server/api/v1/settings"
	v1_smb "github.com/autobutler-org/autobutler/internal/server/api/v1/smb"
	v1_storage "github.com/autobutler-org/autobutler/internal/server/api/v1/storage"
	v1_thumbnails "github.com/autobutler-org/autobutler/internal/server/api/v1/thumbnails"
	v1_version "github.com/autobutler-org/autobutler/internal/server/api/v1/version"
	v1_webdav "github.com/autobutler-org/autobutler/internal/server/api/v1/webdav"
	"github.com/autobutler-org/autobutler/pkg/botel/system"
	"github.com/autobutler-org/autobutler/pkg/util/serverutil"
	"github.com/autobutler-org/autobutler/pkg/util/storageutil"

	"github.com/gin-contrib/static"
	"github.com/gin-gonic/gin"
)

//go:embed public
var public embed.FS

func setupRoutes(engine *gin.Engine, systemCollector *system.Collector) {
	setupRouters(engine, systemCollector)
	setupWebDAV(engine)
	setupStaticRoutes(engine)
}

func setupRouters(engine *gin.Engine, systemCollector *system.Collector) {
	group := engine.Group("/api/v1")
	apiRouters := []serverutil.Router{
		v1_auth.NewRouter(),
		v1_books.NewRouter(),
		v1_files.NewRouter(),
		v1_devices.NewRouter(),
		v1_events.NewRouter(),
		v1_health.NewRouter(systemCollector),
		v1_metrics.NewRouter(),
		v1_migration.NewRouter(),
		v1_photos.NewRouter(),
		v1_plugins.NewRouter(),
		v1_settings.NewRouter(),
		v1_storage.NewRouter(),
		v1_thumbnails.NewRouter(),
		v1_smb.NewRouter(),
		v1_version.NewRouter(),
	}
	for _, r := range apiRouters {
		serverutil.RegisterRouterWithGroup(group, r)
	}
}

func setupWebDAV(engine *gin.Engine) {
	cirrusDir, err := storageutil.GetCirrusDir()
	if err != nil {
		// Cirrus dir setup happens earlier in StartServer via setupServices,
		// so this should not fail. Log and skip if it does.
		slog.Error("webdav: failed to get cirrus dir, WebDAV disabled", "err", err)
		return
	}

	handler := v1_webdav.NewHandler(cirrusDir)
	for _, method := range v1_webdav.WebDAVMethods() {
		engine.Handle(method, "/dav/*filepath", handler)
	}
}

func setupStaticRoutes(engine *gin.Engine) error {
	fs, err := static.EmbedFolder(public, "public")
	if err != nil {
		return err
	}
	engine.Use(static.Serve("/", fs))
	// Read index.html once at startup for the SPA fallback.
	// In dev mode (no built frontend), index.html may not exist — fall back
	// to a plain 404 so the server still starts.
	indexHTML, readErr := public.ReadFile("public/index.html")
	if readErr != nil {
		fmt.Println("[warn] No embedded index.html — SPA fallback disabled (dev mode?)")
	}
	engine.NoRoute(
		func(c *gin.Context) {
			if indexHTML != nil {
				// Serve index.html for any unmatched route so Flutter's client-side
				// router can read the URL path (e.g. /health, /photos) and navigate.
				// Using c.Data instead of c.FileFromFS to avoid http.FileServer's
				// redirect behavior that strips the path to /.
				c.Data(http.StatusOK, "text/html; charset=utf-8", indexHTML)
				return
			}
			c.String(http.StatusNotFound, "404 page not found")
		},
	)
	return nil
}
