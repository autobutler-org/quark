package server

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/gin-gonic/gin"
)

const loginPath = "/api/v0/auth/login"

// newLoginEngine builds the production engine with the middleware stack and a
// stub login handler, so the rate limiter sees the client IP the real server
// would.
func newLoginEngine(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	engine, err := newEngine()
	if err != nil {
		t.Fatalf("newEngine: %v", err)
	}
	middleware.Use(engine, deputil.NewDependencies())
	engine.POST(loginPath, func(c *gin.Context) { c.Status(http.StatusOK) })
	return engine
}

func login(engine *gin.Engine, remoteAddr, forwardedFor string) int {
	req := httptest.NewRequest(http.MethodPost, loginPath, nil)
	req.RemoteAddr = remoteAddr
	if forwardedFor != "" {
		req.Header.Set("X-Forwarded-For", forwardedFor)
	}
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w.Code
}

// hammerUntilLimited sends up to 50 logins and reports whether any came back
// 429. The auth limiter's burst is 10, so a single bucket trips well inside 50.
func hammerUntilLimited(engine *gin.Engine, remoteAddr string, forwardedFor func(i int) string) bool {
	for i := range 50 {
		if login(engine, remoteAddr, forwardedFor(i)) == http.StatusTooManyRequests {
			return true
		}
	}
	return false
}

// TestLoginRateLimit_SpoofedForwardedForFromRemotePeer verifies that a client
// connecting from a non-loopback address cannot dodge the login limit by
// sending a fresh X-Forwarded-For on every attempt: the header is ignored and
// every attempt counts against the peer's own bucket.
func TestLoginRateLimit_SpoofedForwardedForFromRemotePeer(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "")
	engine := newLoginEngine(t)

	limited := hammerUntilLimited(engine, "203.0.113.7:40000", func(i int) string {
		return fmt.Sprintf("198.51.100.%d", i)
	})
	if !limited {
		t.Fatal("rotating X-Forwarded-For from 203.0.113.7 never hit 429; the header bypassed the rate limit")
	}
}

// TestLoginRateLimit_ForwardedForFromLoopbackProxy verifies that a request
// arriving from loopback — the tsnet remote-access proxy — is attributed to
// the forwarded client, so one tailnet peer exhausting its bucket does not
// lock out another.
func TestLoginRateLimit_ForwardedForFromLoopbackProxy(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "")
	engine := newLoginEngine(t)

	limited := hammerUntilLimited(engine, "127.0.0.1:40000", func(int) string {
		return "100.64.0.1"
	})
	if !limited {
		t.Fatal("repeated logins forwarded for 100.64.0.1 never hit 429")
	}
	if code := login(engine, "127.0.0.1:40000", "100.64.0.2"); code == http.StatusTooManyRequests {
		t.Fatal("a second tailnet peer was rate limited by the first peer's attempts")
	}
}

// TestLoginRateLimit_TrustedProxiesOverride verifies that QUARK_TRUSTED_PROXIES
// replaces the loopback default: a peer inside the configured range is trusted
// to forward, and loopback no longer is.
func TestLoginRateLimit_TrustedProxiesOverride(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "10.0.0.0/8")
	engine := newLoginEngine(t)

	limited := hammerUntilLimited(engine, "10.1.2.3:40000", func(int) string {
		return "203.0.113.7"
	})
	if !limited {
		t.Fatal("repeated logins forwarded for 203.0.113.7 never hit 429")
	}
	if code := login(engine, "10.1.2.3:40000", "203.0.113.8"); code == http.StatusTooManyRequests {
		t.Fatal("a second client behind the trusted ingress was rate limited by the first")
	}

	spoofed := hammerUntilLimited(engine, "127.0.0.1:40000", func(i int) string {
		return fmt.Sprintf("198.51.100.%d", i)
	})
	if !spoofed {
		t.Fatal("loopback was still trusted to forward after QUARK_TRUSTED_PROXIES replaced the default")
	}
}

// TestNewEngine_InvalidTrustedProxies verifies that a bad QUARK_TRUSTED_PROXIES
// fails startup instead of silently trusting nothing or everything.
func TestNewEngine_InvalidTrustedProxies(t *testing.T) {
	t.Setenv("QUARK_TRUSTED_PROXIES", "10.0.0.0/8,not-an-ip")
	gin.SetMode(gin.TestMode)
	if _, err := newEngine(); err == nil {
		t.Fatal("newEngine accepted QUARK_TRUSTED_PROXIES=10.0.0.0/8,not-an-ip")
	}
}
