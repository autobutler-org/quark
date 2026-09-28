package v0_albums_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_albums "github.com/autobutler-org/quark/internal/server/api/v0/albums"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/albumutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// TestListAlbumItems_SortByNameAscending verifies GET /albums/:id/items
// accepts sort=name&order=asc and orders the response accordingly (#2509).
func TestListAlbumItems_SortByNameAscending(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	if _, err := storageutil.GetFilesDir(); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	ctx := context.Background()
	q := database.Queries
	user, err := q.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	album, err := albumutil.CreateAlbum(ctx, albumutil.CreateAlbumParams{UserID: user.ID, Queries: q, Name: "Trip"})
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"charlie.jpg", "alpha.jpg", "bravo.jpg"} {
		if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.Album.ID, RelPath: name}); err != nil {
			t.Fatal(err)
		}
	}

	deps := deputil.NewDependencies().
		WithStorageService(storageutil.NewStorageService(systemDevice{})).
		WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: user.ID, IsAdmin: true})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_albums.NewRouter())

	path := "/api/v0/albums/" + strconv.FormatInt(album.Album.ID, 10) + "/items?sort=name&order=asc"
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("GET %s returned %d: %s", path, w.Code, w.Body.String())
	}

	var items []v0_albums.AlbumItemJSON
	if err := json.Unmarshal(w.Body.Bytes(), &items); err != nil {
		t.Fatalf("decode: %v", err)
	}
	want := []string{"alpha.jpg", "bravo.jpg", "charlie.jpg"}
	if len(items) != len(want) {
		t.Fatalf("got %d items, want %d", len(items), len(want))
	}
	for i, name := range want {
		if items[i].RelPath != name {
			t.Fatalf("item[%d] = %q, want %q", i, items[i].RelPath, name)
		}
	}
}
