package v0_thumbnails_test

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	v0_thumbnails "github.com/autobutler-org/quark/internal/server/api/v0/thumbnails"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// noDevices reports no external devices, so every serial falls back to the
// internal files directory.
type noDevices struct{}

func (noDevices) DetectDevices() ([]storageutil.Device, error) {
	return nil, nil
}

// TestGetThumbnail_PathEscapingFilesDir asks for an image that sits next to the
// files directory rather than inside it. The fallback path must refuse it with
// 404 instead of generating a thumbnail from outside the files directory.
func TestGetThumbnail_PathEscapingFilesDir(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatalf("failed to resolve files dir: %v", err)
	}
	for _, name := range []string{"secret.jpg", "secret.mp4"} {
		if err := os.WriteFile(filepath.Join(filepath.Dir(filesDir), name), []byte("not in files"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	deps := deputil.NewDependencies().
		WithStorageService(storageutil.NewStorageService(noDevices{}))
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(gin.Recovery())
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_thumbnails.NewRouter())

	for _, path := range []string{
		"/api/v0/thumbnails/../secret.jpg",
		"/api/v0/thumbnails/../secret.jpg?serial=unknown",
		"/api/v0/thumbnails/../secret.mp4",
		"/api/v0/thumbnails/%2e%2e/secret.jpg",
	} {
		t.Run(path, func(t *testing.T) {
			w := httptest.NewRecorder()
			engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
			if w.Code != http.StatusNotFound {
				t.Fatalf("GET %s = %d, want 404: %s", path, w.Code, w.Body.String())
			}
		})
	}
}
