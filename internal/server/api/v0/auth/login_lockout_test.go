package v0_auth_test

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/ratelimitutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// TestLoginUser_LockoutIs429WithRetryAfter drives POST /auth/login past the
// guard's threshold: wrong passwords stay 401, then even the right password
// is 429 with Retry-After in whole seconds, the same for a username that does
// not exist, until the lockout runs out (#1861).
func TestLoginUser_LockoutIs429WithRetryAfter(t *testing.T) {
	database := dbtest.NewDB(t)
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, FilesDir: t.TempDir(), Username: "admin", AuthKey: dbtest.AuthKey("admin-password"), SaltSecret: dbtest.SaltSecret}); err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_000_000, 0)
	guard := ratelimitutil.NewLoginGuard(ratelimitutil.LoginGuardParams{
		Now:           func() time.Time { return now },
		PairThreshold: 3,
		BaseLockout:   90 * time.Second,
	})
	deps := deputil.NewDependencies().WithDatabase(database).WithLoginGuard(guard)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())
	login := func(username, password string) (int, string, map[string]any) {
		w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": username, "authKey": dbtest.AuthKey(password)})
		return w.Code, w.Header().Get("Retry-After"), decodeBody(t, w)
	}

	for _, username := range []string{"admin", "ghost"} {
		for range 3 {
			if code, _, _ := login(username, "wrong"); code != http.StatusUnauthorized {
				t.Fatalf("%s wrong password = %d, want 401", username, code)
			}
		}
	}
	code, retry, adminBody := login("admin", "admin-password")
	if code != http.StatusTooManyRequests || retry != "90" {
		t.Fatalf("right password during lockout = %d Retry-After %q, want 429 \"90\"", code, retry)
	}
	if _, ok := adminBody["token"]; ok {
		t.Fatal("locked-out login carried a token")
	}
	code, retry, ghostBody := login("ghost", "anything")
	if code != http.StatusTooManyRequests || retry != "90" || ghostBody["error"] != adminBody["error"] {
		t.Fatalf("unknown username = %d %q %v, want the admin's 429 %v", code, retry, ghostBody, adminBody)
	}

	now = now.Add(89*time.Second + time.Millisecond)
	if _, retry, _ := login("admin", "admin-password"); retry != "1" {
		t.Fatalf("Retry-After with under a second left = %q, want \"1\"", retry)
	}
	now = now.Add(time.Second)
	if code, _, body := login("admin", "admin-password"); code != http.StatusOK || body["token"] == "" {
		t.Fatalf("login after the lockout = %d %v", code, body)
	}
}
