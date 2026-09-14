package v0_favorites_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_favorites "github.com/autobutler-org/quark/internal/server/api/v0/favorites"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

// systemDevice is the internal drive at "/", whose files directory lives under
// HOME.
type systemDevice struct{}

func (systemDevice) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Internal", MountPoint: "/", IsInternal: true}}, nil
}

// TestFavorites_Access lists, checks and toggles only the favorites a
// non-admin can read, while an admin sees every one (#1904). Favorites stay
// shared until #1912; only what shows up in them is filtered.
func TestFavorites_Access(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	if _, err := storageutil.GetFilesDir(); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	ctx := context.Background()
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{Username: "bob", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	for _, rel := range []string{"shared/a.jpg", "private/b.jpg"} {
		if _, err := favoritesutil.ToggleFavorite(ctx, database.Queries, "", rel); err != nil {
			t.Fatal(err)
		}
	}
	deps := deputil.NewDependencies().
		WithStorageService(storageutil.NewStorageService(systemDevice{})).
		WithDatabase(database)
	principal := accessutil.System

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_favorites.NewRouter())

	list := func() []string {
		t.Helper()
		w := doFavReq(engine, http.MethodGet, "/api/v0/photos/favorites", nil)
		var items []struct {
			RelPath string `json:"relPath"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &items); w.Code != http.StatusOK || err != nil {
			t.Fatalf("list = %d %s: %v", w.Code, w.Body.String(), err)
		}
		paths := make([]string, 0, len(items))
		for _, item := range items {
			paths = append(paths, item.RelPath)
		}
		slices.Sort(paths)
		return paths
	}
	status := func(method, path string, body []byte) int {
		return doFavReq(engine, method, path, body).Code
	}

	if got := list(); len(got) != 2 {
		t.Errorf("admin favorites = %v, want both", got)
	}

	principal = accessutil.Principal{UserID: user.ID}
	if got := list(); len(got) != 0 {
		t.Errorf("favorites with no rows = %v, want none", got)
	}
	if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
		RelPath: "shared",
		UserID:  sql.NullInt64{Int64: user.ID, Valid: true},
		Level:   accessutil.Read.String(),
	}); err != nil {
		t.Fatal(err)
	}
	if got := list(); !slices.Equal(got, []string{"shared/a.jpg"}) {
		t.Errorf("favorites with a read share = %v, want [shared/a.jpg]", got)
	}
	for path, want := range map[string]int{
		"/api/v0/photos/favorite?relPath=shared/a.jpg":  http.StatusOK,
		"/api/v0/photos/favorite?relPath=private/b.jpg": http.StatusNotFound,
	} {
		if got := status(http.MethodGet, path, nil); got != want {
			t.Errorf("GET %s = %d, want %d", path, got, want)
		}
	}
	if got := status(http.MethodPost, "/api/v0/photos/favorite", []byte(`{"relPath":"private/b.jpg"}`)); got != http.StatusNotFound {
		t.Errorf("toggle an unreadable photo = %d, want 404", got)
	}
	if got := status(http.MethodPost, "/api/v0/photos/favorite", []byte(`{"relPath":"shared/a.jpg"}`)); got != http.StatusOK {
		t.Errorf("toggle a readable photo = %d, want 200", got)
	}
}
