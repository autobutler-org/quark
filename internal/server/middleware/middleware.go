package middleware

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

// authRateLimitedPaths are the API paths that require rate limiting.
var authRateLimitedPaths = map[string]bool{
	"/api/v0/auth/login":           true,
	"/api/v0/auth/setup":           true,
	"/api/v0/auth/recover":         true,
	"/api/v0/storage/devices/role": true,
}

// vaultRateLimitedPaths are the API paths that use the stricter vault limiter.
var vaultRateLimitedPaths = map[string]bool{
	"/api/v0/vault/unlock": true,
}

// rateLimit is a middleware that enforces per-IP rate limiting on auth endpoints.
// The two limiters live on Dependencies, so they are constructed once with the
// dependency graph and shared by every request the server handles (#1674).
func rateLimit(deps deputil.Dependencies) gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := ratelimitutil.ExtractIP(c.ClientIP())
		path := c.Request.URL.Path
		if vaultRateLimitedPaths[path] {
			if !deps.VaultRateLimiter().Allow(ip) {
				c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many requests, please slow down"})
				c.Abort()
				return
			}
			c.Next()
			return
		}
		if !authRateLimitedPaths[path] {
			c.Next()
			return
		}
		if !deps.AuthRateLimiter().Allow(ip) {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many requests, please slow down"})
			c.Abort()
			return
		}
		c.Next()
	}
}

// queryTokenPrefixes lists the path prefixes for which the ?token= query
// parameter is accepted as authentication. This mechanism exists for endpoints
// where setting an Authorization header is not possible (WebSocket) or
// impractical (media streaming URLs embedded in <video>/<audio> src attributes
// and file download links). All other paths must use Bearer / cookie / Basic.
//
// Keep this list minimal. (#1332)
var queryTokenPrefixes = []string{
	"/api/v0/events",     // WebSocket — new WebSocket() cannot set headers
	"/api/v0/files",      // file download / streaming (src= attribute usage)
	"/api/v0/photos",     // photo serving
	"/api/v0/thumbnails", // thumbnail serving (Image.network src= cannot set headers)
	"/videos/",           // video deep-link player
	"/audio/",            // audio deep-link player
}

// queryTokenAllowed returns true when ?token= auth is permitted for the given
// request path.
func queryTokenAllowed(path string) bool {
	for _, prefix := range queryTokenPrefixes {
		if strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

// authExemptPaths are API paths that don't require a valid session.
var authExemptPaths = map[string]bool{
	"/api/v0/auth/setup":   true,
	"/api/v0/auth/login":   true,
	"/api/v0/auth/recover": true,
	"/api/v0/auth/status":  true,
}

func inject(deps deputil.Dependencies) gin.HandlerFunc {
	return func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	}
}

// trackDevice records the client IP and User-Agent in connected_devices.
// Runs asynchronously so it never blocks the request.
func trackDevice(deps deputil.Dependencies) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()
		if deps.Database() == nil {
			return
		}
		ip := c.ClientIP()
		ua := c.Request.UserAgent()
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			if _, err := deps.Database().Queries.UpsertConnectedDevice(
				ctx,
				db.UpsertConnectedDeviceParams{IpAddress: ip, UserAgent: ua},
			); err != nil {
				slog.Debug("trackDevice: upsert failed", "err", err)
			}
		}()
	}
}

// requireAuth validates the request using a fallthrough chain of auth methods.
// Each method is tried in order; if one fails, the next is attempted. Only if
// ALL methods fail does the request get a 401.
//
// Precedence (highest to lowest):
//  1. Bearer token (Authorization: Bearer <token>)
//  2. Session cookie
//  3. Query parameter (?token=)
//  4. HTTP Basic Auth (Authorization: Basic <base64>)
//
// Exempt paths (setup, login, recover, status) are always allowed through.
// If no users have been set up yet, all requests are allowed through (first-boot).
//
// setupDone caches whether initial setup has been completed. Once true it is
// never re-checked, avoiding a DB query on every request.
func requireAuth(deps deputil.Dependencies) gin.HandlerFunc {
	var setupDone atomic.Bool
	return func(c *gin.Context) {
		path := c.Request.URL.Path

		// Static assets and the Flutter web app don't need auth — the client-side
		// authRedirect (lib/router.dart) gates terms and session, consulting this
		// server's status endpoint. Only /api/ routes require a session.
		if !strings.HasPrefix(path, "/api/") {
			c.Next()
			return
		}

		if authExemptPaths[path] {
			c.Next()
			return
		}

		db := deps.Database()
		if db == nil {
			// Database not yet initialized — fail closed rather than allowing
			// unauthenticated access to API/DAV routes.
			c.AbortWithStatusJSON(http.StatusServiceUnavailable,
				gin.H{"error": "service unavailable"})
			return
		}

		// Check if setup is complete. Once confirmed, cache the result so we
		// don't query the DB on every subsequent request.
		if !setupDone.Load() {
			complete, err := authutil.IsSetupComplete(c.Request.Context(), db.Queries)
			if err != nil {
				// Transient DB failure — fail closed, do not allow unauthenticated
				// access (e.g. SQLite lock or disk hiccup).
				c.AbortWithStatusJSON(http.StatusServiceUnavailable,
					gin.H{"error": "service unavailable"})
				return
			}
			if !complete {
				// Genuine pre-setup state — let the setup wizard through.
				c.Next()
				return
			}
			setupDone.Store(true)
		}

		ctx := c.Request.Context()

		// Collect all candidate tokens from headers/cookie/query.
		// Try each in order — fall through on failure.
		//
		// The ?token= query parameter is intentionally restricted to a small
		// allowlist of paths where header-based auth is not possible (WebSocket
		// event stream) or where the URL appears only in server logs that are
		// already privileged (video/audio streaming, file downloads). Accepting
		// it on all endpoints would leak session tokens into browser history,
		// HTTP proxy logs, and Gin's access log. (#1332)
		var tokens []string
		if auth := c.GetHeader("Authorization"); strings.HasPrefix(auth, "Bearer ") {
			tokens = append(tokens, strings.TrimPrefix(auth, "Bearer "))
		}
		if cookie, err := c.Cookie("session"); err == nil && cookie != "" {
			tokens = append(tokens, cookie)
		}
		if q := c.Query("token"); q != "" && queryTokenAllowed(path) {
			tokens = append(tokens, q)
		}

		for _, t := range tokens {
			username, userID, err := authutil.ValidateSession(ctx, db.Queries, t)
			if err == nil {
				c = ctxutil.With(c, "username", username)
				c = ctxutil.With(c, "userID", userID)
				c.Next()
				return
			}
		}

		// Fall back to HTTP Basic Auth.
		if username, password, ok := c.Request.BasicAuth(); ok {
			validUser, userID, err := authutil.ValidateBasicAuth(ctx, db.Queries, username, password)
			if err == nil {
				c = ctxutil.With(c, "username", validUser)
				c = ctxutil.With(c, "userID", userID)
				c.Next()
				return
			}
		}

		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		c.Abort()
	}
}

func Use(router *gin.Engine, deps deputil.Dependencies) {
	// CORS: the Flutter web UI is embedded and served from the same origin, so
	// cross-origin access is only needed for native clients (iOS/Android, curl,
	// desktop apps). Those clients authenticate via Authorization: Bearer or
	// Basic — neither requires AllowCredentials.
	//
	// Combining AllowAllOrigins with AllowCredentials is rejected by browsers
	// anyway, and is a defense-in-depth problem: it signals that any origin may
	// send credentialed requests. Dropping AllowCredentials means the browser
	// will not forward session cookies cross-origin (also enforced by the
	// SameSite=Strict flag on the session cookie itself).
	config := cors.DefaultConfig()
	config.AllowAllOrigins = true
	config.AllowMethods = []string{"POST", "GET", "PUT", "PATCH", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{
		"Authorization",
		"Content-Type",
		"Origin",
		"Accept",
		"X-Requested-With",
	}
	config.ExposeHeaders = []string{"Content-Length"}
	config.AllowCredentials = false // see comment above
	config.MaxAge = 12 * time.Hour
	router.Use(cors.New(config))
	router.Use(inject(deps))
	router.Use(trackDevice(deps))
	router.Use(rateLimit(deps))
	router.Use(requireAuth(deps))
}

// RequireAdmin is a middleware that rejects requests from non-admin users with
// 403 Forbidden. It must be applied after requireAuth (which sets "username").
func RequireAdmin(deps deputil.Dependencies) gin.HandlerFunc {
	return func(c *gin.Context) {
		username, ok := ctxutil.Get[string](c, "username")
		if !ok || username == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		db := deps.Database()
		if db == nil {
			c.AbortWithStatusJSON(http.StatusServiceUnavailable, gin.H{"error": "service unavailable"})
			return
		}
		isAdmin, err := authutil.IsAdmin(c.Request.Context(), db.Queries, username)
		if err != nil || !isAdmin {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			return
		}
		c.Next()
	}
}
