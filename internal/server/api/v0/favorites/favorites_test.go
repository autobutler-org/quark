package v0_favorites_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_favorites "github.com/autobutler-org/quark/internal/server/api/v0/favorites"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
	_ "modernc.org/sqlite"
)

func newFavoritesTestDB(t *testing.T) (*sql.DB, *db.Queries) {
	t.Helper()
	database := dbtest.NewDB(t)
	return database.Db, database.Queries
}

func newFavoritesEngine(t *testing.T, sqlDB *sql.DB, queries *db.Queries) *gin.Engine {
	t.Helper()
	deps := deputil.NewDependencies().WithDatabase(&db.DatabaseSqlc{Db: sqlDB, Queries: queries})
	founder, err := queries.CreateUser(context.Background(), db.CreateUserParams{Username: "founder", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatal(err)
	}
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: founder.ID, IsAdmin: true})
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_favorites.NewRouter())
	return engine
}

func doFavReq(engine *gin.Engine, method, path string, body []byte) *httptest.ResponseRecorder {
	var r *bytes.Reader
	if body != nil {
		r = bytes.NewReader(body)
	} else {
		r = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, r)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestToggleFavorite_AddsThenRemoves verifies POST /photos/favorite toggles
// the favorite state: first call adds, second call removes.
func TestToggleFavorite_AddsThenRemoves(t *testing.T) {
	sqlDB, queries := newFavoritesTestDB(t)
	engine := newFavoritesEngine(t, sqlDB, queries)

	body, _ := json.Marshal(map[string]string{
		"relPath":      "photos/sunset.jpg",
		"deviceSerial": "DEV-001",
	})

	// First toggle → added.
	w := doFavReq(engine, http.MethodPost, "/api/v0/photos/favorite", body)
	if w.Code != http.StatusOK {
		t.Fatalf("first toggle returned %d: %s", w.Code, w.Body.String())
	}
	var resp1 struct {
		IsFavorite bool `json:"isFavorite"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp1)
	if !resp1.IsFavorite {
		t.Errorf("first toggle: expected isFavorite=true")
	}

	// Second toggle → removed.
	w2 := doFavReq(engine, http.MethodPost, "/api/v0/photos/favorite", body)
	if w2.Code != http.StatusOK {
		t.Fatalf("second toggle returned %d: %s", w2.Code, w2.Body.String())
	}
	var resp2 struct {
		IsFavorite bool `json:"isFavorite"`
	}
	json.Unmarshal(w2.Body.Bytes(), &resp2)
	if resp2.IsFavorite {
		t.Errorf("second toggle: expected isFavorite=false")
	}
}

// TestToggleFavorite_MissingRelPath verifies POST /photos/favorite returns 400
// when relPath is absent.
func TestToggleFavorite_MissingRelPath(t *testing.T) {
	sqlDB, queries := newFavoritesTestDB(t)
	engine := newFavoritesEngine(t, sqlDB, queries)

	body, _ := json.Marshal(map[string]string{"deviceSerial": "DEV-001"})
	w := doFavReq(engine, http.MethodPost, "/api/v0/photos/favorite", body)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

// TestIsFavorite_FalseWhenNotFavorited verifies GET /photos/favorite returns
// isFavorite=false for a photo that hasn't been toggled.
func TestIsFavorite_FalseWhenNotFavorited(t *testing.T) {
	sqlDB, queries := newFavoritesTestDB(t)
	engine := newFavoritesEngine(t, sqlDB, queries)

	w := doFavReq(engine, http.MethodGet,
		"/api/v0/photos/favorite?relPath=photos%2Funknown.jpg&serial=DEV-001", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /photos/favorite returned %d: %s", w.Code, w.Body.String())
	}
	var resp struct {
		IsFavorite bool `json:"isFavorite"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp.IsFavorite {
		t.Error("expected isFavorite=false for unfavorited photo")
	}
}

// TestIsFavorite_TrueAfterToggle verifies GET /photos/favorite returns true
// after the photo has been toggled.
func TestIsFavorite_TrueAfterToggle(t *testing.T) {
	sqlDB, queries := newFavoritesTestDB(t)
	engine := newFavoritesEngine(t, sqlDB, queries)

	// Add via toggle.
	body, _ := json.Marshal(map[string]string{
		"relPath": "photos/beach.jpg", "deviceSerial": "DEV-002",
	})
	doFavReq(engine, http.MethodPost, "/api/v0/photos/favorite", body)

	// Check.
	w := doFavReq(engine, http.MethodGet,
		"/api/v0/photos/favorite?relPath=photos%2Fbeach.jpg&serial=DEV-002", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET returned %d: %s", w.Code, w.Body.String())
	}
	var resp struct {
		IsFavorite bool `json:"isFavorite"`
	}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if !resp.IsFavorite {
		t.Error("expected isFavorite=true after toggle")
	}
}

// TestIsFavorite_MissingRelPath verifies GET /photos/favorite returns 400
// when relPath query param is absent.
func TestIsFavorite_MissingRelPath(t *testing.T) {
	sqlDB, queries := newFavoritesTestDB(t)
	engine := newFavoritesEngine(t, sqlDB, queries)

	w := doFavReq(engine, http.MethodGet, "/api/v0/photos/favorite", nil)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

// TestListFavorites_Empty verifies GET /photos/favorites returns an empty
// slice when no photos are favorited.
func TestListFavorites_Empty(t *testing.T) {
	sqlDB, queries := newFavoritesTestDB(t)
	engine := newFavoritesEngine(t, sqlDB, queries)

	w := doFavReq(engine, http.MethodGet, "/api/v0/photos/favorites", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /photos/favorites returned %d: %s", w.Code, w.Body.String())
	}
	var items []any
	json.Unmarshal(w.Body.Bytes(), &items)
	if items == nil {
		t.Error("expected empty slice, not null")
	}
}

// TestListFavorites_IncludesAddedPhoto verifies GET /photos/favorites returns
// photos that have been toggled as favorites.
func TestListFavorites_IncludesAddedPhoto(t *testing.T) {
	sqlDB, queries := newFavoritesTestDB(t)
	engine := newFavoritesEngine(t, sqlDB, queries)

	body, _ := json.Marshal(map[string]string{
		"relPath": "photos/mountain.jpg", "deviceSerial": "DEV-003",
	})
	doFavReq(engine, http.MethodPost, "/api/v0/photos/favorite", body)

	w := doFavReq(engine, http.MethodGet, "/api/v0/photos/favorites", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("GET /photos/favorites returned %d: %s", w.Code, w.Body.String())
	}
	var items []struct {
		RelPath      string `json:"relPath"`
		DeviceSerial string `json:"deviceSerial"`
	}
	json.Unmarshal(w.Body.Bytes(), &items)
	if len(items) != 1 {
		t.Fatalf("expected 1 favorite, got %d; body: %s", len(items), w.Body.String())
	}
	if items[0].RelPath != "photos/mountain.jpg" {
		t.Errorf("relPath = %q; want 'photos/mountain.jpg'", items[0].RelPath)
	}
}

// TestFavorites_PerUser verifies two accounts star the same photo
// independently: each has its own isFavorite, its own list and its own
// Favorites album. Both are admins, whose access bypass covers files only
// (#1912).
func TestFavorites_PerUser(t *testing.T) {
	sqlDB, q := newFavoritesTestDB(t)
	ctx := context.Background()
	ids := map[string]int64{}
	for _, name := range []string{"ann", "ben"} {
		user, err := q.CreateUser(ctx, db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		ids[name] = user.ID
	}
	deps := deputil.NewDependencies().WithDatabase(&db.DatabaseSqlc{Db: sqlDB, Queries: q})
	principal := accessutil.Principal{}
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_favorites.NewRouter())

	as := func(name string) { principal = accessutil.Principal{UserID: ids[name], IsAdmin: true} }
	toggle := func() {
		t.Helper()
		if w := doFavReq(engine, http.MethodPost, "/api/v0/photos/favorite", []byte(`{"relPath":"beach.jpg"}`)); w.Code != http.StatusOK {
			t.Fatalf("toggle = %d: %s", w.Code, w.Body.String())
		}
	}
	isFavorite := func() bool {
		t.Helper()
		w := doFavReq(engine, http.MethodGet, "/api/v0/photos/favorite?relPath=beach.jpg", nil)
		var resp struct {
			IsFavorite bool `json:"isFavorite"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &resp); w.Code != http.StatusOK || err != nil {
			t.Fatalf("isFavorite = %d %s: %v", w.Code, w.Body.String(), err)
		}
		return resp.IsFavorite
	}
	listed := func() int {
		t.Helper()
		var items []any
		w := doFavReq(engine, http.MethodGet, "/api/v0/photos/favorites", nil)
		if err := json.Unmarshal(w.Body.Bytes(), &items); w.Code != http.StatusOK || err != nil {
			t.Fatalf("list = %d %s: %v", w.Code, w.Body.String(), err)
		}
		return len(items)
	}

	as("ann")
	toggle()
	as("ben")
	if isFavorite() || listed() != 0 {
		t.Fatal("ben sees ann's favorite")
	}
	toggle()
	as("ann")
	toggle() // ann removes hers
	if isFavorite() || listed() != 0 {
		t.Error("ann's favorite survived her removing it")
	}
	as("ben")
	if !isFavorite() || listed() != 1 {
		t.Error("ann removing her favorite removed ben's")
	}

	annAlbum, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, ids["ann"])
	if err != nil {
		t.Fatal(err)
	}
	benAlbum, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, ids["ben"])
	if err != nil {
		t.Fatal(err)
	}
	if annAlbum.ID == benAlbum.ID {
		t.Fatalf("ann and ben share Favorites album %d", annAlbum.ID)
	}
	if n, _ := q.CountAlbumItems(ctx, benAlbum.ID); n != 1 {
		t.Errorf("ben's Favorites album holds %d items, want 1", n)
	}
	if n, _ := q.CountAlbumItems(ctx, annAlbum.ID); n != 0 {
		t.Errorf("ann's Favorites album holds %d items, want 0", n)
	}
}
