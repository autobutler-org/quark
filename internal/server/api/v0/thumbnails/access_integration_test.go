package v0_thumbnails_test

import (
	"context"
	"database/sql"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
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

// systemDevice is the internal drive at "/", whose files directory is the one
// storageutil.GetFilesDir resolves under HOME, the same directory the
// thumbnail handler falls back to.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// thumbnailHarness serves thumbnails over a real files directory and a
// migrated database, acting as whoever principal names (#1904).
type thumbnailHarness struct {
	engine    *gin.Engine
	filesDir  string
	database  *db.DatabaseSqlc
	userID    int64
	principal *accessutil.Principal
}

// newThumbnailHarness builds the engine. withVFS registers the files namespace,
// which sends plain images down the VFS branch; without it every request takes
// the StorageService branch.
func newThumbnailHarness(t *testing.T, withVFS bool) thumbnailHarness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatal(err)
	}
	svc := storageutil.NewStorageService(systemDevice{})
	database := dbtest.NewDB(t)
	user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{
		Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	deps := deputil.NewDependencies().WithStorageService(svc).WithDatabase(database)
	if withVFS {
		registry := vfs.NewRegistry()
		if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
			t.Fatal(err)
		}
		deps = deps.WithVFSRegistry(registry)
	}
	system := accessutil.System
	principal := &system

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_thumbnails.NewRouter())
	return thumbnailHarness{engine: engine, filesDir: filesDir, database: database, userID: user.ID, principal: principal}
}

func (h thumbnailHarness) asUser()  { *h.principal = accessutil.Principal{UserID: h.userID} }
func (h thumbnailHarness) asAdmin() { *h.principal = accessutil.System }

func (h thumbnailHarness) get(path string) int {
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	return w.Code
}

func (h thumbnailHarness) grantRead(t *testing.T, rel string) {
	t.Helper()
	if err := h.database.Queries.SetUserPathAccess(context.Background(), db.SetUserPathAccessParams{
		RelPath: rel,
		UserID:  sql.NullInt64{Int64: h.userID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
}

func writeJPEG(t *testing.T, filesDir, rel string) {
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
	if err := jpeg.Encode(f, image.NewRGBA(image.Rect(0, 0, 8, 8)), nil); err != nil {
		t.Fatal(err)
	}
}

// TestThumbnailAccess covers both serving branches: a non-admin gets a thumbnail
// only for an image they can read, a thumbnail an admin already cached is not
// served to someone who cannot read its source, and an unknown serial no longer
// falls back to the internal drive for them.
func TestThumbnailAccess(t *testing.T) {
	for _, tc := range []struct {
		name    string
		withVFS bool
	}{
		{"vfs", true},
		{"storage service", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h := newThumbnailHarness(t, tc.withVFS)
			writeJPEG(t, h.filesDir, "shared/a.jpg")
			writeJPEG(t, h.filesDir, "private/b.jpg")

			// The admin warms the cache for both and writes no rows doing so.
			for _, p := range []string{"/api/v0/thumbnails/shared/a.jpg", "/api/v0/thumbnails/private/b.jpg"} {
				if code := h.get(p); code != http.StatusOK {
					t.Fatalf("admin GET %s = %d, want 200", p, code)
				}
			}
			var rows int
			if err := h.database.Db.QueryRow(`SELECT COUNT(*) FROM path_access`).Scan(&rows); err != nil {
				t.Fatal(err)
			}
			if rows != 0 {
				t.Errorf("admin thumbnails wrote %d access rows, want 0", rows)
			}

			h.asUser()
			if code := h.get("/api/v0/thumbnails/shared/a.jpg"); code != http.StatusNotFound {
				t.Errorf("cached thumbnail with no rows = %d, want 404", code)
			}
			h.grantRead(t, "shared")
			for path, want := range map[string]int{
				"/api/v0/thumbnails/shared/a.jpg":             http.StatusOK,
				"/api/v0/thumbnails/private/b.jpg":            http.StatusNotFound,
				"/api/v0/thumbnails/shared/a.jpg?serial=nope": http.StatusNotFound,
			} {
				if code := h.get(path); code != want {
					t.Errorf("user GET %s = %d, want %d", path, code, want)
				}
			}

			h.asAdmin()
			if code := h.get("/api/v0/thumbnails/private/b.jpg"); code != http.StatusOK {
				t.Errorf("admin GET private/b.jpg after the user = %d, want 200", code)
			}
		})
	}
}

// TestThumbnailAccess_ArchiveEntry checks a thumbnail of an entry inside an
// archive is checked against the archive: the check runs before the archive
// branch, so a non-admin gets 404 until the archive is shared with them.
func TestThumbnailAccess_ArchiveEntry(t *testing.T) {
	h := newThumbnailHarness(t, false)
	writeZipWithPNG(t, h.filesDir)
	const entry = "/api/v0/thumbnails/photos.zip/pics/red.png"

	if code := h.get(entry); code != http.StatusOK {
		t.Fatalf("admin GET %s = %d, want 200", entry, code)
	}
	h.asUser()
	if code := h.get(entry); code != http.StatusNotFound {
		t.Errorf("user GET archive entry with no rows = %d, want 404", code)
	}
	h.grantRead(t, "photos.zip")
	if code := h.get(entry); code != http.StatusOK {
		t.Errorf("user GET archive entry with the archive shared = %d, want 200", code)
	}
}
