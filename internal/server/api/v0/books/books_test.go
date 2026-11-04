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
	"github.com/autobutler-org/quark/pkg/vfs"
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

	deps := deputil.NewDependencies().WithVFSRegistry(internalRegistry(t))
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

// internalRegistry holds the internal drive's files namespace, the one the
// books walk reads, over the files directory under HOME.
func internalRegistry(t *testing.T) vfs.Registry {
	t.Helper()
	svc := storageutil.NewStorageService(systemDevice{})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}
	return registry
}

func doGet(engine *gin.Engine, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
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

// serialUsb implements only GetSerial; any other call panics on the nil
// embedded interface.
type serialUsb struct {
	storageutil.UsbDevice
	serial string
}

func (u serialUsb) GetSerial() string { return u.serial }

type driveDetector struct {
	devices []storageutil.Device
}

func (d driveDetector) DetectDevices() ([]storageutil.Device, error) {
	return d.devices, nil
}

// A PDF on a USB drive is a book too, and its entry names that drive. A
// non-book on the same drive is not (#3712).
func TestListBooks_SecondNamespace(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	internalFiles, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(internalFiles, "shelf.pdf"), []byte("internal"), 0o644); err != nil {
		t.Fatal(err)
	}

	usbMount := t.TempDir()
	const serial = "STICK"
	svc := storageutil.NewStorageService(driveDetector{devices: []storageutil.Device{
		{Name: "Internal", MountPoint: "/", IsInternal: true},
		{Name: "USB", MountPoint: usbMount, UsbInfo: serialUsb{serial: serial}},
	}})
	usbFiles, err := storageutil.GetFilesDirForDevice(usbMount)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(usbFiles, "library"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(usbFiles, "library", "novel.epub"), []byte("usb"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(usbFiles, "notes.txt"), []byte("nope"), 0o644); err != nil {
		t.Fatal(err)
	}

	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}

	deps := deputil.NewDependencies().WithVFSRegistry(registry).WithStorageService(svc)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_books.NewRouter())

	w := doGet(engine, "/api/v0/books")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body %s", w.Code, w.Body.String())
	}
	var books []map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &books); err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, book := range books {
		path, _ := book["relPath"].(string)
		drive, _ := book["deviceSerial"].(string)
		got[path] = drive
	}
	want := map[string]string{
		"shelf.pdf":          "",
		"library/novel.epub": serial,
	}
	if len(got) != len(want) {
		t.Fatalf("books = %v, want %v", got, want)
	}
	for path, drive := range want {
		if got[path] != drive {
			t.Errorf("%s deviceSerial = %q, want %q", path, got[path], drive)
		}
	}
}

// A server with no internal files namespace is misconfigured: 500, not a panic.
func TestListBooks_NoNamespace(t *testing.T) {
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	deps := deputil.NewDependencies().WithVFSRegistry(vfs.NewRegistry())
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_books.NewRouter())

	if w := doGet(engine, "/api/v0/books"); w.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want 500", w.Code)
	}
}
