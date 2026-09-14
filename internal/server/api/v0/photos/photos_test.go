package v0_photos_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

func newPhotosEngine(t *testing.T, reg vfs.Registry) *gin.Engine {
	t.Helper()
	deps := deputil.NewDependencies().WithVFSRegistry(reg)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_photos.NewRouter())
	return engine
}

func newPhotosEngineWithNS(t *testing.T) (*gin.Engine, *vfs.MemVFS) {
	t.Helper()
	reg := vfs.NewRegistry()
	mem := vfs.NewMemVFS("files")
	if err := reg.Register(vfs.Namespace{ID: "files", Description: "files"}, mem); err != nil {
		t.Fatalf("Register: %v", err)
	}
	return newPhotosEngine(t, reg), mem
}

func doPhotosReq(engine *gin.Engine, method, path string, body []byte) *httptest.ResponseRecorder {
	var b *bytes.Reader
	if body != nil {
		b = bytes.NewReader(body)
	} else {
		b = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, b)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestCopyPhoto_VFS_CopiesFile verifies POST /photos/copy duplicates a file
// via the VFS path and returns a _copy path.
func TestCopyPhoto_VFS_CopiesFile(t *testing.T) {
	engine, mem := newPhotosEngineWithNS(t)
	ctx := context.Background()

	// Seed original.
	if err := mem.Write(ctx, "/sunset.jpg", strings.NewReader("img"),
		vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	body, _ := json.Marshal(map[string]string{"relPath": "/sunset.jpg"})
	w := doPhotosReq(engine, http.MethodPost, "/api/v0/photos/copy", body)
	if w.Code != http.StatusOK {
		t.Fatalf("copy returned %d: %s", w.Code, w.Body.String())
	}

	var resp struct {
		RelPath string `json:"relPath"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if !strings.Contains(resp.RelPath, "_copy") {
		t.Errorf("RelPath = %q; expected '_copy' in name", resp.RelPath)
	}

	// Original should still exist.
	if _, err := mem.Stat(ctx, "/sunset.jpg"); err != nil {
		t.Error("original file was removed; expected it to persist")
	}

	// Copy should exist.
	if _, err := mem.Stat(ctx, resp.RelPath); err != nil {
		t.Errorf("copy at %q doesn't exist: %v", resp.RelPath, err)
	}
}

// TestCopyPhoto_VFS_NonConflictingName verifies that copying a file twice
// produces distinct names (_copy and _copy_2).
func TestCopyPhoto_VFS_NonConflictingName(t *testing.T) {
	engine, mem := newPhotosEngineWithNS(t)
	ctx := context.Background()

	mem.Write(ctx, "/mountain.jpg", strings.NewReader("img"),
		vfs.WriteOptions{ContentType: "image/jpeg"})

	body, _ := json.Marshal(map[string]string{"relPath": "/mountain.jpg"})

	// First copy → /mountain_copy.jpg
	w1 := doPhotosReq(engine, http.MethodPost, "/api/v0/photos/copy", body)
	if w1.Code != http.StatusOK {
		t.Fatalf("first copy returned %d: %s", w1.Code, w1.Body.String())
	}
	var r1 struct {
		RelPath string `json:"relPath"`
	}
	json.Unmarshal(w1.Body.Bytes(), &r1)

	// Second copy → /mountain_copy_2.jpg (non-conflicting)
	w2 := doPhotosReq(engine, http.MethodPost, "/api/v0/photos/copy", body)
	if w2.Code != http.StatusOK {
		t.Fatalf("second copy returned %d: %s", w2.Code, w2.Body.String())
	}
	var r2 struct {
		RelPath string `json:"relPath"`
	}
	json.Unmarshal(w2.Body.Bytes(), &r2)

	if r1.RelPath == r2.RelPath {
		t.Errorf("both copies got same path %q; expected unique names", r1.RelPath)
	}
}

// TestCopyPhoto_VFS_NotFound verifies POST /photos/copy returns 404 when the
// source file doesn't exist.
func TestCopyPhoto_VFS_NotFound(t *testing.T) {
	engine, _ := newPhotosEngineWithNS(t)

	body, _ := json.Marshal(map[string]string{"relPath": "/ghost.jpg"})
	w := doPhotosReq(engine, http.MethodPost, "/api/v0/photos/copy", body)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

// TestCopyPhoto_MissingRelPath verifies POST /photos/copy returns 400 when
// relPath is absent from the request body.
func TestCopyPhoto_MissingRelPath(t *testing.T) {
	engine, _ := newPhotosEngineWithNS(t)

	body, _ := json.Marshal(map[string]string{})
	w := doPhotosReq(engine, http.MethodPost, "/api/v0/photos/copy", body)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing relPath, got %d: %s", w.Code, w.Body.String())
	}
}

// TestCopyPhoto_InvalidJSON verifies POST /photos/copy returns 400 for
// malformed JSON.
func TestCopyPhoto_InvalidJSON(t *testing.T) {
	engine, _ := newPhotosEngineWithNS(t)

	w := doPhotosReq(engine, http.MethodPost, "/api/v0/photos/copy", []byte("not-json"))
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid JSON, got %d: %s", w.Code, w.Body.String())
	}
}
