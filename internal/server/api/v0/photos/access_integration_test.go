package v0_photos_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// systemDevice is the internal drive at "/", whose files directory is the one
// storageutil.GetFilesDir resolves under HOME.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// photoHarness serves the photo routes over a real files directory, the
// production StorageService-backed VFS and a migrated database, acting as
// whoever principal names (#1904).
type photoHarness struct {
	engine    *gin.Engine
	filesDir  string
	database  *db.DatabaseSqlc
	userID    int64
	principal *accessutil.Principal
}

func newPhotoHarness(t *testing.T) photoHarness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(systemDevice{})
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
	deps := deputil.NewDependencies().WithStorageService(svc).WithVFSRegistry(registry).WithDatabase(database)
	system := accessutil.System
	principal := &system

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_photos.NewRouter())

	h := photoHarness{engine: engine, filesDir: filesDir, database: database, userID: user.ID, principal: principal}
	for _, rel := range []string{"shared/a.jpg", "shared/sub/b.jpg", "private/c.jpg"} {
		h.writeJPEG(t, rel)
	}
	return h
}

func (h photoHarness) writeJPEG(t *testing.T, rel string) {
	t.Helper()
	full := filepath.Join(h.filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(full)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := jpeg.Encode(f, image.NewRGBA(image.Rect(0, 0, 8, 8)), nil); err != nil {
		t.Fatal(err)
	}
}

func (h photoHarness) grant(t *testing.T, rel string, level accessutil.Level) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: rel,
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   level.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

func (h photoHarness) do(method, path, body string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	h.engine.ServeHTTP(w, req)
	return w
}

// total lists one photo and returns the page length and the total.
func (h photoHarness) total(t *testing.T) (int, int) {
	t.Helper()
	w := h.do(http.MethodGet, "/api/v0/photos?limit=1", "")
	var page v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &page); err != nil {
		t.Fatalf("list = %d %s: %v", w.Code, w.Body.String(), err)
	}
	return len(page.Photos), page.Total
}

// expect checks metadata, rotate and copy on one photo.
func (h photoHarness) expect(t *testing.T, rel string, metadata, rotate, copyCode int) {
	t.Helper()
	if w := h.do(http.MethodGet, "/api/v0/photos/metadata?relPath="+rel, ""); w.Code != metadata {
		t.Errorf("metadata %s = %d, want %d: %s", rel, w.Code, metadata, w.Body.String())
	}
	if w := h.do(http.MethodPost, "/api/v0/photos/rotate", `{"relPath":"`+rel+`","rotationQuarters":1}`); w.Code != rotate {
		t.Errorf("rotate %s = %d, want %d: %s", rel, w.Code, rotate, w.Body.String())
	}
	if w := h.do(http.MethodPost, "/api/v0/photos/copy", `{"relPath":"`+rel+`"}`); w.Code != copyCode {
		t.Errorf("copy %s = %d, want %d: %s", rel, w.Code, copyCode, w.Body.String())
	}
}

func (h photoHarness) level(t *testing.T, rel string) string {
	t.Helper()
	var level string
	err := h.database.Db.QueryRow(`SELECT level FROM path_access WHERE rel_path = ?`, rel).Scan(&level)
	if err != nil && err != sql.ErrNoRows {
		t.Fatal(err)
	}
	return level
}

func (h photoHarness) duplicateGroups(t *testing.T) int {
	t.Helper()
	w := h.do(http.MethodGet, "/api/v0/photos/duplicates", "")
	var body struct {
		Groups []json.RawMessage `json:"groups"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("duplicates = %d %s: %v", w.Code, w.Body.String(), err)
	}
	return len(body.Groups)
}

func TestPhotoAccess_AdminSeesEverythingAndWritesNoRows(t *testing.T) {
	h := newPhotoHarness(t)
	if n, total := h.total(t); n != 1 || total != 3 {
		t.Errorf("admin list = %d photos of %d, want 1 of 3", n, total)
	}
	h.expect(t, "private/c.jpg", http.StatusOK, http.StatusOK, http.StatusOK)
	var rows int
	if err := h.database.Db.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 0 {
		t.Errorf("admin photo edits wrote %d access rows, want 0", rows)
	}
}

func TestPhotoAccess_NonAdmin(t *testing.T) {
	h := newPhotoHarness(t)
	for _, rel := range []string{"shared/a.jpg", "private/c.jpg"} {
		if err := h.database.Queries.UpsertPhotoHash(context.Background(), db.UpsertPhotoHashParams{
			RelPath:     rel,
			ContentHash: sql.NullString{String: "same", Valid: true},
		}); err != nil {
			t.Fatal(err)
		}
	}
	if got := h.duplicateGroups(t); got != 1 {
		t.Errorf("admin duplicate groups = %d, want 1", got)
	}
	*h.principal = accessutil.Principal{UserID: h.userID}

	if n, total := h.total(t); n != 0 || total != 0 {
		t.Errorf("list with no rows = %d photos of %d, want none", n, total)
	}
	h.expect(t, "shared/a.jpg", http.StatusNotFound, http.StatusNotFound, http.StatusNotFound)

	h.grant(t, "shared", accessutil.Read)
	if n, total := h.total(t); n != 1 || total != 2 {
		t.Errorf("list with a read share = %d photos of %d, want 1 of 2", n, total)
	}
	if got := h.duplicateGroups(t); got != 0 {
		t.Errorf("duplicate groups with one readable photo = %d, want 0", got)
	}
	h.expect(t, "shared/a.jpg", http.StatusOK, http.StatusForbidden, http.StatusForbidden)
	h.expect(t, "private/c.jpg", http.StatusNotFound, http.StatusNotFound, http.StatusNotFound)

	h.grant(t, "shared", accessutil.Write)
	h.expect(t, "shared/a.jpg", http.StatusOK, http.StatusOK, http.StatusOK)
	if got := h.level(t, "shared/a_copy.jpg"); got != "owner" {
		t.Errorf("copy owner row = %q, want owner", got)
	}
	if got := h.level(t, "shared/a.jpg"); got != "" {
		t.Errorf("source photo gained a %q row, want none", got)
	}
}
