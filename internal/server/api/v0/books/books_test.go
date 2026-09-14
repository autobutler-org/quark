package v0_books_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	v0_books "github.com/autobutler-org/quark/internal/server/api/v0/books"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// newBooksEngine creates a gin engine with the books routes registered.
// It points HOME at a temp dir so GetFilesDir() resolves to a controlled location.
func newBooksEngine(t *testing.T) (*gin.Engine, string) {
	t.Helper()

	// Redirect the data directory to a temp location. The layout under HOME is
	// platform-specific, so ask storageutil for the path rather than hardcoding
	// it — GetFilesDir also creates the directory.
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatalf("failed to resolve files dir: %v", err)
	}

	deps := deputil.NewDependencies()
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_books.NewRouter())
	return engine, filesDir
}

func doGet(engine *gin.Engine, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestListBooks_EmptyDir verifies that an empty files directory returns 200
// with an empty JSON array.
func TestListBooks_EmptyDir(t *testing.T) {
	engine, _ := newBooksEngine(t)

	w := doGet(engine, "/api/v0/books")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var result []any
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to parse body as JSON array: %v", err)
	}
	if len(result) != 0 {
		t.Errorf("expected empty array, got %d items", len(result))
	}
}

// TestListBooks_WithEpub verifies that an .epub file in the files directory
// appears in the response with the correct fields populated.
func TestListBooks_WithEpub(t *testing.T) {
	engine, filesDir := newBooksEngine(t)

	// Create a minimal .epub placeholder.
	epubPath := filepath.Join(filesDir, "test-book.epub")
	if err := os.WriteFile(epubPath, []byte("fake epub content"), 0644); err != nil {
		t.Fatalf("failed to write epub: %v", err)
	}

	w := doGet(engine, "/api/v0/books")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var result []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to parse body: %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("expected 1 book, got %d", len(result))
	}

	book := result[0]
	if book["fileName"] != "test-book.epub" {
		t.Errorf("unexpected fileName: %v", book["fileName"])
	}
	if book["type"] == nil || book["type"] == "" {
		t.Errorf("expected type field to be set")
	}
	if book["mtime"] == nil {
		t.Errorf("expected mtime field to be set")
	}
	if book["size"] == nil {
		t.Errorf("expected size field to be set")
	}
}

// TestListBooks_IgnoresNonBookFiles verifies that non-book files (e.g. .txt, .png)
// are excluded from the response and only recognized book types are returned.
func TestListBooks_IgnoresNonBookFiles(t *testing.T) {
	engine, filesDir := newBooksEngine(t)

	// Write one book and two non-book files.
	files := map[string][]byte{
		"novel.epub": []byte("epub"),
		"readme.txt": []byte("not a book"),
		"cover.png":  []byte("not a book"),
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(filesDir, name), content, 0644); err != nil {
			t.Fatalf("failed to write %s: %v", name, err)
		}
	}

	w := doGet(engine, "/api/v0/books")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var result []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to parse body: %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("expected 1 book (epub only), got %d: %v", len(result), result)
	}
	if result[0]["fileName"] != "novel.epub" {
		t.Errorf("unexpected fileName: %v", result[0]["fileName"])
	}
}

// TestListBooks_PdfIncluded verifies that .pdf files are also returned (PDF is a
// supported book type alongside epub).
func TestListBooks_PdfIncluded(t *testing.T) {
	engine, filesDir := newBooksEngine(t)

	if err := os.WriteFile(filepath.Join(filesDir, "manual.pdf"), []byte("%PDF"), 0644); err != nil {
		t.Fatalf("failed to write pdf: %v", err)
	}

	w := doGet(engine, "/api/v0/books")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var result []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to parse body: %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("expected 1 book (pdf), got %d", len(result))
	}
	if result[0]["fileName"] != "manual.pdf" {
		t.Errorf("unexpected fileName: %v", result[0]["fileName"])
	}
}

// TestListBooks_SubdirectoryRecursion verifies that books nested in subdirectories
// are also returned.
func TestListBooks_SubdirectoryRecursion(t *testing.T) {
	engine, filesDir := newBooksEngine(t)

	subDir := filepath.Join(filesDir, "fiction", "scifi")
	if err := os.MkdirAll(subDir, 0755); err != nil {
		t.Fatalf("failed to create subdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(subDir, "dune.epub"), []byte("dune"), 0644); err != nil {
		t.Fatalf("failed to write epub: %v", err)
	}

	w := doGet(engine, "/api/v0/books")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var result []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &result); err != nil {
		t.Fatalf("failed to parse body: %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("expected 1 book, got %d", len(result))
	}
	relPath, _ := result[0]["relPath"].(string)
	if relPath == "" {
		t.Errorf("expected relPath to be set")
	}
}
