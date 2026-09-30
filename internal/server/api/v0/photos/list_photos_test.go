package v0_photos_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// TestListPhotos_SortByNameAscending verifies GET /photos?sort=name&order=asc
// returns photos ordered by filename rather than the default newest-first.
func TestListPhotos_SortByNameAscending(t *testing.T) {
	engine, mem := newPhotosEngineWithNS(t)
	ctx := context.Background()
	for _, name := range []string{"charlie.jpg", "alpha.jpg", "bravo.jpg"} {
		if err := mem.Write(ctx, "/"+name, strings.NewReader("img"), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
			t.Fatalf("seed %s: %v", name, err)
		}
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos?sort=name&order=asc", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}

	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Photos) != 3 {
		t.Fatalf("got %d photos, want 3", len(resp.Photos))
	}
	want := []string{"alpha.jpg", "bravo.jpg", "charlie.jpg"}
	for i, name := range want {
		if resp.Photos[i].FileName != name {
			t.Fatalf("photo[%d] = %q, want %q", i, resp.Photos[i].FileName, name)
		}
	}
}

// TestListPhotos_DefaultSortUnchanged verifies omitting sort/order still
// returns the historical newest-first order.
func TestListPhotos_DefaultSortUnchanged(t *testing.T) {
	engine, mem := newPhotosEngineWithNS(t)
	ctx := context.Background()
	if err := mem.Write(ctx, "/a.jpg", strings.NewReader("img"), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Photos) != 1 || resp.Photos[0].FileName != "a.jpg" {
		t.Fatalf("unexpected response: %+v", resp)
	}
}

// TestListPhotos_SortByTaken verifies GET /photos?sort=taken orders by the
// stored capture date and reports it as takenAt (#2592).
func TestListPhotos_SortByTaken(t *testing.T) {
	reg := vfs.NewRegistry()
	mem := vfs.NewMemVFS("files")
	if err := reg.Register(vfs.Namespace{ID: "files", Description: "files"}, mem); err != nil {
		t.Fatalf("Register: %v", err)
	}
	database := dbtest.NewDB(t)
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_photos.NewRouter())

	ctx := context.Background()
	taken := map[string]time.Time{
		"old.jpg": time.Date(2019, 7, 4, 12, 0, 0, 0, time.UTC),
		"new.jpg": time.Date(2023, 1, 1, 12, 0, 0, 0, time.UTC),
	}
	for name, at := range taken {
		if err := mem.Write(ctx, "/"+name, strings.NewReader("img"), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
			t.Fatalf("seed %s: %v", name, err)
		}
		if err := database.Queries.UpsertPhotoHash(ctx, db.UpsertPhotoHashParams{
			RelPath: name, TakenAt: sql.NullTime{Time: at, Valid: true}, TakenChecked: true,
		}); err != nil {
			t.Fatal(err)
		}
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos?sort=taken&order=asc", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Photos) != 2 || resp.Photos[0].FileName != "old.jpg" || resp.Photos[1].FileName != "new.jpg" {
		t.Fatalf("photos = %+v, want old.jpg then new.jpg", resp.Photos)
	}
	if got, want := resp.Photos[0].TakenAt, taken["old.jpg"].Unix(); got != want {
		t.Errorf("old.jpg takenAt = %d, want %d", got, want)
	}
}
