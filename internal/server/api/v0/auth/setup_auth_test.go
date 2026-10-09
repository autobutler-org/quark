package v0_auth_test

import (
	"context"
	"net/http"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_auth "github.com/autobutler-org/quark/internal/server/api/v0/auth"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/settingsutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// newSetupEngine mounts the auth router on a fresh Quark whose files
// namespace, when registry holds one, is where the founder's home goes.
func newSetupEngine(t *testing.T, registry vfs.Registry) *gin.Engine {
	t.Helper()
	settingsutil.ResetForTesting(filepath.Join(t.TempDir(), "settings.json"))
	t.Cleanup(func() { settingsutil.ResetForTesting("") })
	deps := deputil.NewDependencies().WithDatabase(dbtest.NewDB(t)).WithVFSRegistry(registry)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_auth.NewRouter())
	return engine
}

// TestSetupAuth_MakesTheFounderAHomeInTheFilesNamespace checks setup makes
// the founding admin's home through the files namespace, not a directory it
// looked up on its own (#2648).
func TestSetupAuth_MakesTheFounderAHomeInTheFilesNamespace(t *testing.T) {
	files := vfs.NewMemVFS("files")
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, files); err != nil {
		t.Fatal(err)
	}
	engine := newSetupEngine(t, registry)

	w := postJSON(engine, "/api/v0/auth/setup", map[string]string{"username": "owner", "authKey": dbtest.AuthKey("long-enough")})
	if w.Code != http.StatusOK {
		t.Fatalf("setup = %d: %s", w.Code, w.Body.String())
	}
	if info, err := files.Stat(context.Background(), "users/owner"); err != nil || !info.IsDir {
		t.Errorf("home of the founder: %+v, %v", info, err)
	}
}

// TestSetupAuth_NoFilesNamespaceIsAServerError checks setup with nowhere to
// put the founder's home fails before it makes an account.
func TestSetupAuth_NoFilesNamespaceIsAServerError(t *testing.T) {
	engine := newSetupEngine(t, vfs.NewRegistry())

	w := postJSON(engine, "/api/v0/auth/setup", map[string]string{"username": "owner", "authKey": dbtest.AuthKey("long-enough")})
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("setup = %d: %s, want 500", w.Code, w.Body.String())
	}
	status := getPath(engine, "/api/v0/auth/status")
	if status.Code != http.StatusOK || decodeBody(t, status)["setup"] != false {
		t.Errorf("status after a refused setup = %d %s, want setup false", status.Code, status.Body.String())
	}
}
