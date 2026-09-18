package v0_files_test

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// newVFSTestEngine builds a test engine whose download handler is backed by a
// LocalVFS (which implements vfs.Seeker), enabling the range-request path.
func newVFSTestEngine(t *testing.T) (*gin.Engine, string) {
	t.Helper()

	dir := t.TempDir()

	localVFS, err := vfs.NewLocalVFS(dir, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS: %v", err)
	}

	reg := vfs.NewRegistry()
	if err := reg.Register(vfs.Namespace{ID: "files"}, localVFS); err != nil {
		t.Fatalf("Register: %v", err)
	}

	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	svc := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithEventBus(eventbus.New()).
		WithVFSRegistry(reg)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_files.NewRouter())
	return engine, dir
}

// TestDownload_RangeRequest verifies that the VFS download path honours HTTP
// range requests (RFC 7233), returning 206 Partial Content and the correct
// byte slice.
func TestDownload_RangeRequest(t *testing.T) {
	engine, vfsRoot := newVFSTestEngine(t)

	// Write a known file into the VFS root so LocalVFS can serve it.
	content := []byte("abcdefghijklmnopqrstuvwxyz") // 26 bytes, a–z
	if err := os.WriteFile(filepath.Join(vfsRoot, "alpha.txt"), content, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	// Request bytes 5–9 ("fghij").
	req := httptest.NewRequest(http.MethodGet, "/api/v0/files/download?filePath=alpha.txt", nil)
	req.Header.Set("Range", "bytes=5-9")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)

	if w.Code != http.StatusPartialContent {
		t.Errorf("expected 206 Partial Content, got %d\nbody: %s", w.Code, w.Body.String())
	}

	got := w.Body.Bytes()
	want := []byte("fghij")
	if !bytes.Equal(got, want) {
		t.Errorf("range body: got %q, want %q", got, want)
	}

	cr := w.Header().Get("Content-Range")
	if cr == "" {
		t.Error("Content-Range header missing from 206 response")
	}
}

// TestDownload_FullFile verifies that a download without a Range header returns
// 200 OK with the complete file content.
func TestDownload_FullFile(t *testing.T) {
	engine, vfsRoot := newVFSTestEngine(t)

	content := []byte("hello vfs world")
	if err := os.WriteFile(filepath.Join(vfsRoot, "hello.txt"), content, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v0/files/download?filePath=hello.txt", nil)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200 OK, got %d\nbody: %s", w.Code, w.Body.String())
	}
	if !bytes.Equal(w.Body.Bytes(), content) {
		t.Errorf("full body: got %q, want %q", w.Body.Bytes(), content)
	}
}

// TestDownload_AcceptRangesHeader verifies that the Accept-Ranges: bytes header
// is set on responses from the VFS Seeker path.
func TestDownload_AcceptRangesHeader(t *testing.T) {
	engine, vfsRoot := newVFSTestEngine(t)

	if err := os.WriteFile(filepath.Join(vfsRoot, "test.bin"), []byte("data"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v0/files/download?filePath=test.bin", nil)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)

	if ar := w.Header().Get("Accept-Ranges"); ar != "bytes" {
		t.Errorf("Accept-Ranges: got %q, want %q", ar, "bytes")
	}
}
