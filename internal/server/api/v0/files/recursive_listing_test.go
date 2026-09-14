package v0_files_test

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"testing"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// newStorageVFSTestEngine mirrors newTestEngine but also registers the "files"
// namespace backed by StorageServiceVFS, the way deputil.DefaultDependencies
// does in production. Without a registry the handlers take their legacy
// non-VFS fallback, so an endpoint test would never exercise the code that
// actually runs on a device.
//
// This is deliberately not download_range_test.go's newVFSTestEngine, which
// registers a LocalVFS for the same namespace — that one cannot reproduce
// anything specific to the StorageService-backed implementation.
func newStorageVFSTestEngine(t *testing.T) (*gin.Engine, string) {
	t.Helper()
	deps, filesDir := newStorageVFSDeps(t)
	return newEngineForDeps(deps), filesDir
}

// newStorageVFSDeps builds the dependency graph behind newStorageVFSTestEngine.
// It is split out so a test that has to reach into deps — at the upload session
// store, for instance (#1629) — gets the same wiring instead of a second copy
// of it that drifts.
func newStorageVFSDeps(t *testing.T) (deputil.Dependencies, string) {
	t.Helper()

	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("failed to create files dir: %v", err)
	}

	svc := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	registry := vfs.NewRegistry()
	if err := registry.Register(
		vfs.Namespace{ID: "files", Description: "Primary vault file store (files)"},
		vfs.NewStorageServiceVFS(svc, "files"),
	); err != nil {
		t.Fatalf("failed to register files namespace: %v", err)
	}

	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithEventBus(eventbus.New()).
		WithUploadSessions(newTestSessionStore(mountPoint))

	return deps, filesDir
}

// newTestSessionStore stages chunked uploads under the test's own mount point.
// The production default sits in the real data directory, which a test must
// never write to.
func newTestSessionStore(mountPoint string) *uploadutil.SessionStore {
	return uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{
		StagingDir: filepath.Join(mountPoint, "quark", "data", "tmp", "upload-sessions"),
	})
}

// newEngineForDeps registers the files routes against a given dependency graph.
func newEngineForDeps(deps deputil.Dependencies) *gin.Engine {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_files.NewRouter())
	return engine
}

func writeFixture(t *testing.T, filesDir, rel string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(full), err)
	}
	if err := os.WriteFile(full, []byte("fixture "+rel), 0644); err != nil {
		t.Fatalf("write %s: %v", full, err)
	}
}

type fileEntry struct {
	Name    string `json:"name"`
	DirPath string `json:"dirPath"`
	IsDir   bool   `json:"isDir"`
}

// decodeFilePaths pulls the returned files' DirPath values — the API-relative
// path a client would use directly — out of the response. Directories are
// dropped; these listings are about which files are reachable.
func decodeFilePaths(t *testing.T, body []byte) []string {
	t.Helper()
	var entries []fileEntry
	if err := json.Unmarshal(body, &entries); err != nil {
		t.Fatalf("decode response: %v\nbody: %s", err, body)
	}
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir {
			continue
		}
		out = append(out, e.DirPath)
	}
	return out
}

// The reported symptom: the Docs page was empty on load because every existing
// .qdoc lived in a subfolder, and /files/by-type only ever saw the storage
// root (#1605).
func TestListFilesByType_FindsNestedDocs(t *testing.T) {
	engine, filesDir := newStorageVFSTestEngine(t)

	writeFixture(t, filesDir, "root.qdoc")
	writeFixture(t, filesDir, "sub/deep.qdoc")
	writeFixture(t, filesDir, "sub/nested/deeper.qdoc")
	writeFixture(t, filesDir, "sub/ignored.txt")

	w := doRequest(engine, http.MethodGet, "/api/v0/files/by-type?fileType=qdoc", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	got := decodeFilePaths(t, w.Body.Bytes())
	for _, want := range []string{"root.qdoc", "sub/deep.qdoc", "sub/nested/deeper.qdoc"} {
		if !slices.Contains(got, want) {
			t.Errorf("expected %q in the by-type listing, got %v", want, got)
		}
	}
	if slices.Contains(got, "sub/ignored.txt") {
		t.Errorf("by-type returned a file of the wrong type: %v", got)
	}
	if len(got) != 3 {
		t.Errorf("expected exactly 3 docs, got %d: %v", len(got), got)
	}
}

// Recent files reads the same recursive listing.
func TestListRecentFiles_FindsNestedFiles(t *testing.T) {
	engine, filesDir := newStorageVFSTestEngine(t)

	writeFixture(t, filesDir, "root.txt")
	writeFixture(t, filesDir, "sub/nested/deep.txt")

	w := doRequest(engine, http.MethodGet, "/api/v0/files/recent", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	got := decodeFilePaths(t, w.Body.Bytes())
	if !slices.Contains(got, "sub/nested/deep.txt") {
		t.Errorf("recent files missed the nested file, got %v", got)
	}
}

// Ordinary browsing must stay one level deep — list_files passes
// Recursive:false, and a recursive listing there would flood the browser.
func TestListFiles_StaysAtOneLevel(t *testing.T) {
	engine, filesDir := newStorageVFSTestEngine(t)

	writeFixture(t, filesDir, "root.txt")
	writeFixture(t, filesDir, "sub/deep.txt")

	w := doRequest(engine, http.MethodGet, "/api/v0/files", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	got := decodeFilePaths(t, w.Body.Bytes())
	if slices.Contains(got, "sub/deep.txt") {
		t.Errorf("plain listing should not descend into subfolders, got %v", got)
	}
}
