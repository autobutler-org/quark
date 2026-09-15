package v0_thumbnails_test

import (
	"archive/zip"
	"bytes"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_thumbnails "github.com/autobutler-org/quark/internal/server/api/v0/thumbnails"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// fakeDetector reports one internal device mounted at a temp directory.
type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Device", MountPoint: f.mountPoint, IsInternal: true}}, nil
}

// newThumbnailEngine builds the thumbnails router over a temp HOME, so the
// thumbnail cache and default files directory stay inside the test. With
// withVFS the files namespace is a LocalVFS; without it every read goes
// through the StorageService. It returns the directory files go in.
func newThumbnailEngine(t *testing.T, withVFS bool) (*gin.Engine, string) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())

	mountPoint := t.TempDir()
	deps := deputil.NewDependencies().
		WithDatabase(dbtest.NewDB(t)).
		WithStorageService(storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint}))

	dir, err := storageutil.GetFilesDirForDevice(mountPoint)
	if err != nil {
		t.Fatalf("GetFilesDirForDevice: %v", err)
	}
	if withVFS {
		dir = t.TempDir()
		localVFS, err := vfs.NewLocalVFS(dir, "files")
		if err != nil {
			t.Fatalf("NewLocalVFS: %v", err)
		}
		reg := vfs.NewRegistry()
		if err := reg.Register(vfs.Namespace{ID: "files"}, localVFS); err != nil {
			t.Fatalf("Register: %v", err)
		}
		deps = deps.WithVFSRegistry(reg)
	}

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		// These tests are about serving, not access, so they act as an admin
		// (#1904). access_integration_test.go covers a non-admin.
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_thumbnails.NewRouter())
	return engine, dir
}

// pngBytes encodes a small image as PNG.
func pngBytes(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 32, 32))
	img.Set(3, 3, color.RGBA{R: 255, A: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("png.Encode: %v", err)
	}
	return buf.Bytes()
}

// writeZipWithPNG writes photos.zip into dir holding pics/red.png.
func writeZipWithPNG(t *testing.T, dir string) {
	t.Helper()
	var archive bytes.Buffer
	zw := zip.NewWriter(&archive)
	w, err := zw.Create("pics/red.png")
	if err != nil {
		t.Fatalf("zip Create: %v", err)
	}
	if _, err := w.Write(pngBytes(t)); err != nil {
		t.Fatalf("zip Write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip Close: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "photos.zip"), archive.Bytes(), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
}

func get(engine *gin.Engine, path string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	return w
}

// expectSmallPNG fails unless w is a 96x96 PNG thumbnail.
func expectSmallPNG(t *testing.T, w *httptest.ResponseRecorder) {
	t.Helper()
	if w.Code != http.StatusOK {
		t.Fatalf("got %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "image/png" {
		t.Errorf("Content-Type: got %q, want image/png", ct)
	}
	cfg, err := png.DecodeConfig(w.Body)
	if err != nil {
		t.Fatalf("body is not a PNG: %v", err)
	}
	if cfg.Width != 96 || cfg.Height != 96 {
		t.Errorf("thumbnail size: got %dx%d, want 96x96", cfg.Width, cfg.Height)
	}
}

// TestGetThumbnail_ArchiveEntry covers the file browser inside a zip: it asks
// for /thumbnails/<archive>/<entry>, which used to 500 because stat-ing a path
// through a regular file fails with ENOTDIR rather than ENOENT.
func TestGetThumbnail_ArchiveEntry(t *testing.T) {
	for name, withVFS := range map[string]bool{"vfs": true, "storage": false} {
		t.Run(name, func(t *testing.T) {
			engine, dir := newThumbnailEngine(t, withVFS)
			writeZipWithPNG(t, dir)

			expectSmallPNG(t, get(engine, "/api/v0/thumbnails/photos.zip/pics/red.png?size=sm"))
			// The second request is answered from the cache entry the first wrote.
			expectSmallPNG(t, get(engine, "/api/v0/thumbnails/photos.zip/pics/red.png?size=sm"))

			// The client shows the file icon for all of these.
			for _, path := range []string{
				"/api/v0/thumbnails/photos.zip/pics/missing.png?size=sm",
				"/api/v0/thumbnails/photos.zip/pics/camera.dng?size=sm",
				"/api/v0/thumbnails/photos.zip/pics/clip.mp4?size=sm",
			} {
				if w := get(engine, path); w.Code != http.StatusNotFound {
					t.Errorf("%s: got %d, want 404: %s", path, w.Code, w.Body.String())
				}
			}
		})
	}
}

// TestGetThumbnail_FolderNamedLikeArchive: a folder called album.zip is still a
// folder, and the images in it get ordinary thumbnails.
func TestGetThumbnail_FolderNamedLikeArchive(t *testing.T) {
	engine, dir := newThumbnailEngine(t, true)
	if err := os.MkdirAll(filepath.Join(dir, "album.zip"), 0755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "album.zip", "red.png"), pngBytes(t), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	expectSmallPNG(t, get(engine, "/api/v0/thumbnails/album.zip/red.png?size=sm"))
}

// TestGetThumbnail_PathThroughFileIsNotFound: a path that treats a regular
// file as a folder is a missing file, not a server error.
func TestGetThumbnail_PathThroughFileIsNotFound(t *testing.T) {
	engine, _ := newThumbnailEngine(t, false)
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatalf("GetFilesDir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "notes.txt"), []byte("hi"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	if w := get(engine, "/api/v0/thumbnails/notes.txt/pic.jpg?size=sm"); w.Code != http.StatusNotFound {
		t.Errorf("got %d, want 404: %s", w.Code, w.Body.String())
	}
}
