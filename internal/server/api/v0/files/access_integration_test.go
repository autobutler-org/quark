package v0_files_test

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
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

// accessHarness is the files router over a real device directory, the
// production StorageService-backed VFS and a migrated database, acting as one
// signed-in user (#1903).
type accessHarness struct {
	engine   *gin.Engine
	filesDir string
	database *db.DatabaseSqlc
	userID   int64
}

func newAccessHarness(t *testing.T, admin bool) accessHarness {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	principal := accessutil.Principal{UserID: user.ID, IsAdmin: admin}
	deps := deputil.NewDependencies().
		WithStorageService(svc).
		WithVFSRegistry(registry).
		WithEventBus(eventbus.New()).
		WithDatabase(database).
		WithUploadSessions(newTestSessionStore(mountPoint))

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_files.NewRouter())
	return accessHarness{engine: engine, filesDir: filesDir, database: database, userID: user.ID}
}

func (h accessHarness) grant(t *testing.T, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: accessutil.Canonical(rel),
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

func (h accessHarness) get(path string) *httptest.ResponseRecorder {
	return doRequest(h.engine, http.MethodGet, path, nil, "")
}

// names lists a folder and returns the entry names, sorted.
func (h accessHarness) names(t *testing.T, rootDir string) []string {
	t.Helper()
	w := h.get("/api/v0/files?rootDir=" + url.QueryEscape(rootDir))
	if w.Code != http.StatusOK {
		t.Fatalf("list %q returned %d: %s", rootDir, w.Code, w.Body.String())
	}
	var entries []fileEntry
	if err := json.Unmarshal(w.Body.Bytes(), &entries); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, strings.TrimRight(e.Name, "/"))
	}
	slices.Sort(names)
	return names
}

func (h accessHarness) rowCount(t *testing.T) int {
	t.Helper()
	var n int
	if err := h.database.Db.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func (h accessHarness) expectStatus(t *testing.T, want int, paths ...string) {
	t.Helper()
	for _, p := range paths {
		if w := h.get(p); w.Code != want {
			t.Errorf("GET %s = %d, want %d: %s", p, w.Code, want, w.Body.String())
		}
	}
}

// writeZip writes an archive holding one entry, inside.txt.
func writeZip(t *testing.T, filesDir, rel string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(full)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	zw := zip.NewWriter(f)
	w, err := zw.Create("inside.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("inside")); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
}

func TestAccess_NoRowsListsAnEmptyRoot(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "a.txt")
	writeFixture(t, h.filesDir, "dir/b.txt")

	if got := h.names(t, ""); len(got) != 0 {
		t.Errorf("root listing = %v, want empty", got)
	}
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files?rootDir=dir",
		"/api/v0/files/stat?filePath=a.txt",
		"/api/v0/files/download?filePath=a.txt",
		"/api/v0/files/download?filePath=dir",
	)
}

func TestAccess_ReadShareCanListAndDownload(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "shared/f.txt")
	writeFixture(t, h.filesDir, "shared/sub/g.txt")
	writeFixture(t, h.filesDir, "other.txt")
	writeZip(t, h.filesDir, "shared/a.zip")
	writeZip(t, h.filesDir, "private/b.zip")
	h.grant(t, "shared", accessutil.Read)

	if got, want := h.names(t, ""), []string{"shared"}; !slices.Equal(got, want) {
		t.Errorf("root listing = %v, want %v", got, want)
	}
	if got, want := h.names(t, "shared"), []string{"a.zip", "f.txt", "sub"}; !slices.Equal(got, want) {
		t.Errorf("shared listing = %v, want %v", got, want)
	}
	w := h.get("/api/v0/files/download?filePath=shared/f.txt")
	if w.Code != http.StatusOK || w.Body.String() != "fixture shared/f.txt" {
		t.Errorf("download = %d %q", w.Code, w.Body.String())
	}
	h.expectStatus(t, http.StatusOK,
		"/api/v0/files/stat?filePath=shared/sub/g.txt",
		"/api/v0/files/list-archive?filePath=shared/a.zip",
		"/api/v0/files/download-archive-file?filePath=shared/a.zip&entryPath=inside.txt",
	)
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files/download?filePath=other.txt",
		"/api/v0/files/list-archive?filePath=private/b.zip",
		"/api/v0/files/download-archive-file?filePath=private/b.zip&entryPath=inside.txt",
	)
}

func TestAccess_DeepShareShowsBreadcrumbs(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "Family/Bob/x.txt")
	writeFixture(t, h.filesDir, "Family/Alice/y.txt")
	writeFixture(t, h.filesDir, "Family/notes.txt")
	writeFixture(t, h.filesDir, "Work/z.txt")
	h.grant(t, "Family/Bob", accessutil.Read)

	for rootDir, want := range map[string][]string{
		"":           {"Family"},
		"Family":     {"Bob"},
		"Family/Bob": {"x.txt"},
	} {
		if got := h.names(t, rootDir); !slices.Equal(got, want) {
			t.Errorf("listing %q = %v, want %v", rootDir, got, want)
		}
	}
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files?rootDir=Work",
		"/api/v0/files?rootDir=Family/Alice",
		"/api/v0/files/stat?filePath=Family",
		"/api/v0/files/download?filePath=Family/notes.txt",
	)
}

func TestAccess_SymlinkOutOfAShareIsNotFound(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "private/secret.txt")
	writeFixture(t, h.filesDir, "shared/f.txt")
	if err := os.Symlink(filepath.Join(h.filesDir, "private", "secret.txt"),
		filepath.Join(h.filesDir, "shared", "link.txt")); err != nil {
		t.Fatal(err)
	}
	h.grant(t, "shared", accessutil.Read)

	if got, want := h.names(t, "shared"), []string{"f.txt"}; !slices.Equal(got, want) {
		t.Errorf("shared listing = %v, want %v", got, want)
	}
	h.expectStatus(t, http.StatusNotFound, "/api/v0/files/download?filePath=shared/link.txt")

	// Downloading the folder zips it; the link must not carry the secret in.
	w := h.get("/api/v0/files/download?filePath=shared")
	if w.Code != http.StatusOK {
		t.Fatalf("folder download = %d: %s", w.Code, w.Body.String())
	}
	zr, err := zip.NewReader(bytes.NewReader(w.Body.Bytes()), int64(w.Body.Len()))
	if err != nil {
		t.Fatalf("read zip: %v", err)
	}
	zipped := make([]string, 0, len(zr.File))
	for _, f := range zr.File {
		zipped = append(zipped, f.Name)
	}
	if want := []string{"f.txt"}; !slices.Equal(zipped, want) {
		t.Errorf("zipped entries = %v, want %v", zipped, want)
	}
}

// An unknown serial used to fall back to the internal drive (#1903), which
// would have served a path granted there under a device the caller named.
func TestAccess_UnknownSerialIsNotFound(t *testing.T) {
	h := newAccessHarness(t, false)
	writeFixture(t, h.filesDir, "a.txt")
	h.grant(t, "", accessutil.Owner)

	h.expectStatus(t, http.StatusOK, "/api/v0/files/download?filePath=a.txt")
	h.expectStatus(t, http.StatusNotFound,
		"/api/v0/files/download?filePath=a.txt&serial=NOPE",
		"/api/v0/files/stat?filePath=a.txt&serial=NOPE",
	)
}

func TestAccess_AdminSeesEverything(t *testing.T) {
	h := newAccessHarness(t, true)
	writeFixture(t, h.filesDir, "a.txt")
	writeFixture(t, h.filesDir, "dir/b.txt")

	if got, want := h.names(t, ""), []string{"a.txt", "dir"}; !slices.Equal(got, want) {
		t.Errorf("admin root listing = %v, want %v", got, want)
	}
	h.expectStatus(t, http.StatusOK,
		"/api/v0/files?rootDir=dir",
		"/api/v0/files/stat?filePath=dir/b.txt",
		"/api/v0/files/download?filePath=dir/b.txt",
	)
	if n := h.rowCount(t); n != 0 {
		t.Errorf("path_access rows after admin requests = %d, want 0", n)
	}
}
