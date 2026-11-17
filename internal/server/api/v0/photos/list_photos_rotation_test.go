package v0_photos_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

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

// TestListPhotos_CarriesRotation: each photo carries its saved rotation, the
// half of the thumbnail version a client cannot get from the mtime (#4217).
func TestListPhotos_CarriesRotation(t *testing.T) {
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
	for _, name := range []string{"plain.jpg", "turned.jpg"} {
		if err := mem.Write(ctx, "/"+name, strings.NewReader("img"), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
			t.Fatalf("seed %s: %v", name, err)
		}
	}
	if err := database.Queries.UpsertPhotoRotation(ctx, db.UpsertPhotoRotationParams{
		RelPath: "turned.jpg", RotationQuarters: 3,
	}); err != nil {
		t.Fatal(err)
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos?sort=name&order=asc", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Photos) != 2 {
		t.Fatalf("got %d photos, want 2: %s", len(resp.Photos), w.Body.String())
	}
	got := map[string]int64{}
	for _, p := range resp.Photos {
		got[p.FileName] = p.RotationQuarters
	}
	if got["plain.jpg"] != 0 || got["turned.jpg"] != 3 {
		t.Errorf("rotations = %v, want plain.jpg 0 and turned.jpg 3", got)
	}
	// The flattened summary still reads as before.
	if !strings.Contains(w.Body.String(), `"fileName":"turned.jpg"`) || !strings.Contains(w.Body.String(), `"rotationQuarters":3`) {
		t.Errorf("body = %s, want fileName and rotationQuarters side by side", w.Body.String())
	}
}
