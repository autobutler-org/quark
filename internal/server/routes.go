package server

import (
	"embed"
	"log/slog"
	"net/http"

	v0_admin "github.com/autobutler-org/quark/internal/server/api/v0/admin"
	v0_albums "github.com/autobutler-org/quark/internal/server/api/v0/albums"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	v0_books "github.com/autobutler-org/quark/internal/server/api/v0/books"
	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/cirrus"
	v0_devices "github.com/autobutler-org/quark/internal/server/api/v0/devices"
	v0_events "github.com/autobutler-org/quark/internal/server/api/v0/events"
	v0_favorites "github.com/autobutler-org/quark/internal/server/api/v0/favorites"
	v0_health "github.com/autobutler-org/quark/internal/server/api/v0/health"

	v0_migration "github.com/autobutler-org/quark/internal/server/api/v0/migration"
	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	v0_settings "github.com/autobutler-org/quark/internal/server/api/v0/settings"
	v0_smb "github.com/autobutler-org/quark/internal/server/api/v0/smb"
	v0_storage "github.com/autobutler-org/quark/internal/server/api/v0/storage"
	v0_thumbnails "github.com/autobutler-org/quark/internal/server/api/v0/thumbnails"
	v0_vault "github.com/autobutler-org/quark/internal/server/api/v0/vault"
	v0_version "github.com/autobutler-org/quark/internal/server/api/v0/version"
	v0_videos "github.com/autobutler-org/quark/internal/server/api/v0/videos"
	v1_plugins "github.com/autobutler-org/quark/internal/server/api/v1/plugins"
	v1_vfs "github.com/autobutler-org/quark/internal/server/api/v1/vfs"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/healthutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-contrib/static"
	"github.com/gin-gonic/gin"
)

//go:embed public
var public embed.FS

func setupRoutes(engine *gin.Engine, systemCollector *healthutil.Collector, deps deputil.Dependencies) error {
	setupRouters(engine, systemCollector, deps)
	return setupStaticRoutes(engine)
}

func setupRouters(engine *gin.Engine, systemCollector *healthutil.Collector, deps deputil.Dependencies) {
	v1group := engine.Group("/api/v1")
	v1Routers := []serverutil.Router{
		v1_vfs.NewRouter(),
		v1_plugins.NewRouter(),
	}
	for _, router := range v1Routers {
		serverutil.RegisterRouterWithGroup(v1group, router)
	}

	group := engine.Group("/api/v0")
	apiRouters := []serverutil.Router{
		v0_auth.NewRouter(),
		v0_books.NewRouter(),
		v0_files.NewRouter(),
		v0_devices.NewRouter(),
		v0_events.NewRouter(),
		v0_health.NewRouter(systemCollector),
		v0_migration.NewRouter(),
		v0_albums.NewRouter(),
		v0_favorites.NewRouter(),
		v0_photos.NewRouter(),
		v0_settings.NewRouter(),
		v0_storage.NewRouter(),
		v0_thumbnails.NewRouter(),
		v0_smb.NewRouter(),
		v0_vault.NewRouter(),
		v0_version.NewRouter(),
		v0_videos.NewRouter(),
	}
	for _, r := range apiRouters {
		serverutil.RegisterRouterWithGroup(group, r)
	}

	// Admin-only routes — wrapped with RequireAdmin middleware.
	adminGroup := group.Group("", middleware.RequireAdmin(deps))
	serverutil.RegisterRouterWithGroup(adminGroup, v0_admin.NewRouter())
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
		slog.Warn("No embedded index.html — SPA fallback disabled (dev mode?)")
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
