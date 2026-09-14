package v0_albums

import (
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
	_ "modernc.org/sqlite"
)

// --- buildTree (pure function, no DB needed) ---

func ptr64(v int64) *int64 { return &v }

func TestBuildTree_EmptyInput(t *testing.T) {
	result := buildTree(nil)
	if len(result) != 0 {
		t.Errorf("expected empty, got %d items", len(result))
	}
}

func TestBuildTree_AllRoots(t *testing.T) {
	albums := []AlbumJSON{
		{ID: 1, Name: "Alpha"},
		{ID: 2, Name: "Beta"},
		{ID: 3, Name: "Gamma"},
	}
	roots := buildTree(albums)
	if len(roots) != 3 {
		t.Fatalf("expected 3 roots, got %d", len(roots))
	}
}

func TestBuildTree_TwoLevels(t *testing.T) {
	albums := []AlbumJSON{
		{ID: 1, Name: "Parent"},
		{ID: 2, Name: "Child", ParentID: ptr64(1)},
	}
	roots := buildTree(albums)
	if len(roots) != 1 {
		t.Fatalf("expected 1 root, got %d", len(roots))
	}
	if len(roots[0].Children) != 1 || roots[0].Children[0].Name != "Child" {
		t.Errorf("expected Child under Parent, got %+v", roots[0].Children)
	}
}

func TestBuildTree_ThreeLevels(t *testing.T) {
	albums := []AlbumJSON{
		{ID: 1, Name: "Grandparent"},
		{ID: 2, Name: "Parent", ParentID: ptr64(1)},
		{ID: 3, Name: "Child", ParentID: ptr64(2)},
	}
	roots := buildTree(albums)
	if len(roots) != 1 {
		t.Fatalf("expected 1 root, got %d", len(roots))
	}
	if len(roots[0].Children) != 1 {
		t.Fatalf("expected 1 child of root, got %d", len(roots[0].Children))
	}
	if len(roots[0].Children[0].Children) != 1 {
		t.Fatalf("expected 1 grandchild, got %d", len(roots[0].Children[0].Children))
	}
	if roots[0].Children[0].Children[0].Name != "Child" {
		t.Errorf("unexpected grandchild name: %q", roots[0].Children[0].Children[0].Name)
	}
}

func TestBuildTree_MultipleChildrenPerParent(t *testing.T) {
	albums := []AlbumJSON{
		{ID: 1, Name: "Root"},
		{ID: 2, Name: "A", ParentID: ptr64(1)},
		{ID: 3, Name: "B", ParentID: ptr64(1)},
		{ID: 4, Name: "C", ParentID: ptr64(1)},
	}
	roots := buildTree(albums)
	if len(roots) != 1 {
		t.Fatalf("expected 1 root, got %d", len(roots))
	}
	if len(roots[0].Children) != 3 {
		t.Errorf("expected 3 children, got %d", len(roots[0].Children))
	}
}

func TestBuildTree_OrphanDropped(t *testing.T) {
	// Child whose parent doesn't exist: dropped (not a root, parent not found).
	albums := []AlbumJSON{
		{ID: 1, Name: "Root"},
		{ID: 2, Name: "Orphan", ParentID: ptr64(999)},
	}
	roots := buildTree(albums)
	if len(roots) != 1 {
		t.Errorf("expected 1 root (orphan dropped), got %d", len(roots))
	}
}

// --- Album SQL query layer ---

func newAlbumDB(t *testing.T) *db.Queries {
	t.Helper()
	return dbtest.NewDB(t).Queries
}

func TestCreateAndListAlbums(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	a, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Vacation"})
	if err != nil {
		t.Fatalf("CreateAlbum: %v", err)
	}
	if a.Name != "Vacation" {
		t.Errorf("expected 'Vacation', got %q", a.Name)
	}

	all, err := q.ListAlbums(ctx)
	if err != nil {
		t.Fatalf("ListAlbums: %v", err)
	}
	if len(all) != 1 {
		t.Errorf("expected 1 album, got %d", len(all))
	}
}

func TestDeleteAlbum(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	a, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "ToDelete"})
	if err := q.DeleteAlbum(ctx, a.ID); err != nil {
		t.Fatalf("DeleteAlbum: %v", err)
	}
	all, _ := q.ListAlbums(ctx)
	if len(all) != 0 {
		t.Errorf("expected 0 albums after delete, got %d", len(all))
	}
}

func TestRenameAlbum(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	a, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Old"})
	renamed, err := q.RenameAlbum(ctx, db.RenameAlbumParams{Name: "New", ID: a.ID})
	if err != nil {
		t.Fatalf("RenameAlbum: %v", err)
	}
	if renamed.Name != "New" {
		t.Errorf("expected 'New', got %q", renamed.Name)
	}
}

func TestAddAndListAlbumItems(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Beach"})
	item, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{
		AlbumID:      album.ID,
		DeviceSerial: "sda1",
		RelPath:      "photos/sunset.jpg",
	})
	if err != nil {
		t.Fatalf("AddPhotoToAlbum: %v", err)
	}
	if item.RelPath != "photos/sunset.jpg" {
		t.Errorf("expected relPath 'photos/sunset.jpg', got %q", item.RelPath)
	}

	items, _ := q.ListAlbumItems(ctx, album.ID)
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d", len(items))
	}
}

func TestAddPhotoToAlbum_Idempotent(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Summer"})
	params := db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: "pic.jpg"}
	if _, err := q.AddPhotoToAlbum(ctx, params); err != nil {
		t.Fatalf("first add: %v", err)
	}
	if _, err := q.AddPhotoToAlbum(ctx, params); err != nil {
		t.Fatalf("second add (should be idempotent): %v", err)
	}
	count, _ := q.CountAlbumItems(ctx, album.ID)
	if count != 1 {
		t.Errorf("expected 1 item after idempotent add, got %d", count)
	}
}

func TestRemovePhotoFromAlbum(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Winter"})
	q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: "snow.jpg"})
	if err := q.RemovePhotoFromAlbum(ctx, db.RemovePhotoFromAlbumParams{
		AlbumID: album.ID, RelPath: "snow.jpg",
	}); err != nil {
		t.Fatalf("RemovePhotoFromAlbum: %v", err)
	}
	count, _ := q.CountAlbumItems(ctx, album.ID)
	if count != 0 {
		t.Errorf("expected 0 items after remove, got %d", count)
	}
}

func TestDeleteAlbum_CascadesItems(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Cascade"})
	q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: "a.jpg"})
	q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: "b.jpg"})

	if err := q.DeleteAlbum(ctx, album.ID); err != nil {
		t.Fatalf("DeleteAlbum: %v", err)
	}
	items, _ := q.ListAlbumItems(ctx, album.ID)
	if len(items) != 0 {
		t.Errorf("expected 0 items after cascade delete, got %d", len(items))
	}
}

func TestCountAlbumItems(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Count"})
	for i, path := range []string{"a.jpg", "b.jpg", "c.jpg"} {
		q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: path})
		count, _ := q.CountAlbumItems(ctx, album.ID)
		if count != int64(i+1) {
			t.Errorf("after %d adds: expected %d, got %d", i+1, i+1, count)
		}
	}
}

func TestListRootAlbums(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	root, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Root"})
	q.CreateAlbum(ctx, db.CreateAlbumParams{
		Name:     "Child",
		ParentID: sql.NullInt64{Int64: root.ID, Valid: true},
	})

	roots, err := q.ListRootAlbums(ctx)
	if err != nil {
		t.Fatalf("ListRootAlbums: %v", err)
	}
	if len(roots) != 1 || roots[0].Name != "Root" {
		t.Errorf("expected 1 root album 'Root', got %+v", roots)
	}
}

func TestListChildAlbums(t *testing.T) {
	q := newAlbumDB(t)
	ctx := context.Background()

	parent, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Parent"})
	q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "C1", ParentID: sql.NullInt64{Int64: parent.ID, Valid: true}})
	q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "C2", ParentID: sql.NullInt64{Int64: parent.ID, Valid: true}})

	children, err := q.ListChildAlbums(ctx, sql.NullInt64{Int64: parent.ID, Valid: true})
	if err != nil {
		t.Fatalf("ListChildAlbums: %v", err)
	}
	if len(children) != 2 {
		t.Errorf("expected 2 children, got %d", len(children))
	}
}

// --- System album guards (HTTP) ---

func newAlbumEngine(t *testing.T) (*gin.Engine, *db.Queries) {
	t.Helper()
	database := dbtest.NewDB(t)
	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), NewRouter())
	return engine, database.Queries
}

func doAlbumReq(engine *gin.Engine, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, bytes.NewReader([]byte(body)))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestSystemAlbumGuards checks that every album mutation refuses the Favorites
// album, both as the album acted on and as a parent to nest under.
func TestSystemAlbumGuards(t *testing.T) {
	engine, q := newAlbumEngine(t)
	ctx := context.Background()
	fav, err := favoritesutil.EnsureFavoritesAlbum(ctx, q)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	user, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Trips"})
	if err != nil {
		t.Fatalf("CreateAlbum: %v", err)
	}
	photo := `{"deviceSerial":"","relPath":"a.jpg"}`

	cases := []struct {
		name, method, path, body string
	}{
		{"delete", http.MethodDelete, fmt.Sprintf("/api/v0/albums/%d", fav.ID), ""},
		{"rename", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/rename", fav.ID), `{"name":"Mine"}`},
		{"move system album", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/move", fav.ID), fmt.Sprintf(`{"parentId":%d}`, user.ID)},
		{"move under system album", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/move", user.ID), fmt.Sprintf(`{"parentId":%d}`, fav.ID)},
		{"create under system album", http.MethodPost, "/api/v0/albums", fmt.Sprintf(`{"name":"Child","parentId":%d}`, fav.ID)},
		{"add item", http.MethodPost, fmt.Sprintf("/api/v0/albums/%d/items", fav.ID), photo},
		{"remove item", http.MethodDelete, fmt.Sprintf("/api/v0/albums/%d/items", fav.ID), photo},
	}
	// Seed the item so a successful remove would be observable.
	if _, err := favoritesutil.ToggleFavorite(ctx, q, "", "a.jpg"); err != nil {
		t.Fatalf("ToggleFavorite: %v", err)
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if w := doAlbumReq(engine, tc.method, tc.path, tc.body); w.Code != http.StatusForbidden {
				t.Fatalf("%s %s = %d, want 403: %s", tc.method, tc.path, w.Code, w.Body.String())
			}
		})
	}

	got, err := q.GetAlbum(ctx, fav.ID)
	if err != nil {
		t.Fatalf("Favorites album is gone: %v", err)
	}
	if got.Name != "Favorites" || got.ParentID.Valid {
		t.Errorf("Favorites album changed: %+v", got)
	}
	if n, _ := q.CountAlbumItems(ctx, fav.ID); n != 1 {
		t.Errorf("Favorites items = %d, want 1", n)
	}
	if u, _ := q.GetAlbum(ctx, user.ID); u.ParentID.Valid {
		t.Errorf("user album was moved under Favorites")
	}
	children, _ := q.ListChildAlbums(ctx, sql.NullInt64{Int64: fav.ID, Valid: true})
	if len(children) != 0 {
		t.Errorf("album created under Favorites: %+v", children)
	}

	// A user album is still fully mutable.
	if w := doAlbumReq(engine, http.MethodDelete, fmt.Sprintf("/api/v0/albums/%d", user.ID), ""); w.Code != http.StatusNoContent {
		t.Errorf("deleting a user album = %d, want 204", w.Code)
	}
}
