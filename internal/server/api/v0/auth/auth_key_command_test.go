package v0_auth_test

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/cmd/quark/authkey"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/internal/server/middleware"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// TestAuthKeyCommand_SignsInAScript is #2713's acceptance: the key
// quark auth-key prints for a password, against a Quark behind its real auth
// middleware, is the key that Quark takes at /auth/login and as the password
// of HTTP Basic, and the password itself is still refused.
func TestAuthKeyCommand_SignsInAScript(t *testing.T) {
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	t.Cleanup(func() { settingsutil.ResetForTesting("") })
	database := dbtest.NewDB(t)
	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	middleware.Use(engine, deps)
	t.Cleanup(deps.Background().Wait)
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())
	quark := httptest.NewServer(engine)
	t.Cleanup(quark.Close)

	authKey := func() string {
		t.Helper()
		cmd := authkey.Cmd()
		var out bytes.Buffer
		cmd.SetOut(&out)
		cmd.SetIn(strings.NewReader("script-password\n"))
		cmd.SetArgs([]string{"--host", quark.URL, "-u", "script"})
		if err := cmd.Execute(); err != nil {
			t.Fatalf("quark auth-key: %v", err)
		}
		return strings.TrimSuffix(out.String(), "\n")
	}

	// The account is made with the key the command derives before it exists,
	// as the app's setup page does with the salt of a name nobody has yet.
	key := authKey()
	if _, err := authutil.Setup(context.Background(), authutil.SetupParams{Database: database, Files: vfs.NewMemVFS("files"), Username: "script", AuthKey: key, SaltSecret: settingsutil.AuthSaltSecret}); err != nil {
		t.Fatalf("Setup: %v", err)
	}
	if again := authKey(); again != key {
		t.Fatalf("the key changed once the account existed: %q, then %q", key, again)
	}

	if w := postJSON(engine, "/api/v0/auth/login", map[string]string{"username": "script", "authKey": key}); w.Code != http.StatusOK {
		t.Errorf("login with the printed key = %d: %s", w.Code, w.Body)
	}
	for _, tc := range []struct {
		name, password string
		want           int
	}{
		{"the printed key", key, http.StatusOK},
		{"the raw password", "script-password", http.StatusUpgradeRequired},
	} {
		req := httptest.NewRequest(http.MethodGet, "/api/v0/auth/sessions", nil)
		req.SetBasicAuth("script", tc.password)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		if w.Code != tc.want {
			t.Errorf("HTTP Basic with %s = %d, want %d: %s", tc.name, w.Code, tc.want, w.Body)
		}
	}
}
