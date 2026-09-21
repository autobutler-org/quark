package v0_albums

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
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

// newAlbumDB returns queries over a fresh database and an account to own
// albums.
func newAlbumDB(t *testing.T) (*db.Queries, int64) {
	t.Helper()
	q := dbtest.NewDB(t).Queries
	return q, newOwner(t, q)
}

// newOwner creates the account the tests' albums belong to.
func newOwner(t *testing.T, q *db.Queries) int64 {
	t.Helper()
	user, err := q.CreateUser(context.Background(), db.CreateUserParams{Username: "founder", PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	return user.ID
}

func TestCreateAndListAlbums(t *testing.T) {
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	a, err := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Vacation"})
	if err != nil {
		t.Fatalf("CreateAlbum: %v", err)
	}
	if a.Name != "Vacation" {
		t.Errorf("expected 'Vacation', got %q", a.Name)
	}

	all, err := q.ListAlbums(ctx, owner)
	if err != nil {
		t.Fatalf("ListAlbums: %v", err)
	}
	if len(all) != 1 {
		t.Errorf("expected 1 album, got %d", len(all))
	}
}

func TestDeleteAlbum(t *testing.T) {
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	a, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "ToDelete"})
	if err := q.DeleteAlbum(ctx, db.DeleteAlbumParams{ID: a.ID, UserID: owner}); err != nil {
		t.Fatalf("DeleteAlbum: %v", err)
	}
	all, _ := q.ListAlbums(ctx, owner)
	if len(all) != 0 {
		t.Errorf("expected 0 albums after delete, got %d", len(all))
	}
}

func TestRenameAlbum(t *testing.T) {
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	a, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Old"})
	renamed, err := q.RenameAlbum(ctx, db.RenameAlbumParams{Name: "New", ID: a.ID, UserID: owner})
	if err != nil {
		t.Fatalf("RenameAlbum: %v", err)
	}
	if renamed.Name != "New" {
		t.Errorf("expected 'New', got %q", renamed.Name)
	}
}

func TestAddAndListAlbumItems(t *testing.T) {
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Beach"})
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
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Summer"})
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
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Winter"})
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
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Cascade"})
	q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: "a.jpg"})
	q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: "b.jpg"})

	if err := q.DeleteAlbum(ctx, db.DeleteAlbumParams{ID: album.ID, UserID: owner}); err != nil {
		t.Fatalf("DeleteAlbum: %v", err)
	}
	items, _ := q.ListAlbumItems(ctx, album.ID)
	if len(items) != 0 {
		t.Errorf("expected 0 items after cascade delete, got %d", len(items))
	}
}

func TestCountAlbumItems(t *testing.T) {
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	album, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Count"})
	for i, path := range []string{"a.jpg", "b.jpg", "c.jpg"} {
		q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: album.ID, RelPath: path})
		count, _ := q.CountAlbumItems(ctx, album.ID)
		if count != int64(i+1) {
			t.Errorf("after %d adds: expected %d, got %d", i+1, i+1, count)
		}
	}
}

func TestListRootAlbums(t *testing.T) {
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	root, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Root"})
	q.CreateAlbum(ctx, db.CreateAlbumParams{
		UserID:   owner,
		Name:     "Child",
		ParentID: sql.NullInt64{Int64: root.ID, Valid: true},
	})

	roots, err := q.ListRootAlbums(ctx, owner)
	if err != nil {
		t.Fatalf("ListRootAlbums: %v", err)
	}
	if len(roots) != 1 || roots[0].Name != "Root" {
		t.Errorf("expected 1 root album 'Root', got %+v", roots)
	}
}

func TestListChildAlbums(t *testing.T) {
	q, owner := newAlbumDB(t)
	ctx := context.Background()

	parent, _ := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Parent"})
	q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "C1", ParentID: sql.NullInt64{Int64: parent.ID, Valid: true}})
	q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "C2", ParentID: sql.NullInt64{Int64: parent.ID, Valid: true}})

	children, err := q.ListChildAlbums(ctx, sql.NullInt64{Int64: parent.ID, Valid: true})
	if err != nil {
		t.Fatalf("ListChildAlbums: %v", err)
	}
	if len(children) != 2 {
		t.Errorf("expected 2 children, got %d", len(children))
	}
}

// --- System album guards (HTTP) ---

func newAlbumEngine(t *testing.T) (*gin.Engine, *db.Queries, int64) {
	t.Helper()
	database := dbtest.NewDB(t)
	owner := newOwner(t, database.Queries)
	deps := deputil.NewDependencies().WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.Principal{UserID: owner, IsAdmin: true})
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), NewRouter())
	return engine, database.Queries, owner
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
	engine, q, owner := newAlbumEngine(t)
	ctx := context.Background()
	fav, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	user, err := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Trips"})
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
	if _, err := favoritesutil.ToggleFavorite(ctx, q, owner, "", "a.jpg"); err != nil {
		t.Fatalf("ToggleFavorite: %v", err)
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if w := doAlbumReq(engine, tc.method, tc.path, tc.body); w.Code != http.StatusForbidden {
				t.Fatalf("%s %s = %d, want 403: %s", tc.method, tc.path, w.Code, w.Body.String())
			}
		})
	}

	got, err := q.GetAlbum(ctx, db.GetAlbumParams{ID: fav.ID, UserID: owner})
	if err != nil {
		t.Fatalf("Favorites album is gone: %v", err)
	}
	if got.Name != "Favorites" || got.ParentID.Valid {
		t.Errorf("Favorites album changed: %+v", got)
	}
	if n, _ := q.CountAlbumItems(ctx, fav.ID); n != 1 {
		t.Errorf("Favorites items = %d, want 1", n)
	}
	if u, _ := q.GetAlbum(ctx, db.GetAlbumParams{ID: user.ID, UserID: owner}); u.ParentID.Valid {
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

// --- Album name rules (HTTP) ---

const (
	conflictMessage = "an album with that name already exists here"
	slashMessage    = "album names cannot contain /"
)

// TestAlbumNameRules checks the 409 and 400 answers for create, rename and
// move: names are unique among siblings ignoring case, root albums (Favorites
// included) are siblings, and a name cannot contain /.
func TestAlbumNameRules(t *testing.T) {
	engine, q, owner := newAlbumEngine(t)
	ctx := context.Background()
	if _, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner); err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	mustCreate := func(name string, parent sql.NullInt64) db.PhotoAlbum {
		t.Helper()
		a, err := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: name, ParentID: parent})
		if err != nil {
			t.Fatalf("CreateAlbum(%q): %v", name, err)
		}
		return a
	}
	trips := mustCreate("Trips", sql.NullInt64{})
	beach := mustCreate("Beach", sql.NullInt64{})
	japan := mustCreate("Japan", sql.NullInt64{Int64: trips.ID, Valid: true})
	rootJapan := mustCreate("japan", sql.NullInt64{})
	nestedBeach := mustCreate("BEACH", sql.NullInt64{Int64: trips.ID, Valid: true})
	nestedFavorites := mustCreate("Favorites", sql.NullInt64{Int64: trips.ID, Valid: true})

	cases := []struct {
		name, method, path, body string
		wantCode                 int
		wantMessage              string
	}{
		{"create root clash", http.MethodPost, "/api/v0/albums", `{"name":"Trips"}`, http.StatusConflict, conflictMessage},
		{"create root case-only clash", http.MethodPost, "/api/v0/albums", `{"name":"tRiPs"}`, http.StatusConflict, conflictMessage},
		{"create nested case-only clash", http.MethodPost, "/api/v0/albums", fmt.Sprintf(`{"name":"JAPAN","parentId":%d}`, trips.ID), http.StatusConflict, conflictMessage},
		{"create user favorites at root", http.MethodPost, "/api/v0/albums", `{"name":"favorites"}`, http.StatusConflict, conflictMessage},
		{"create with slash", http.MethodPost, "/api/v0/albums", `{"name":"Trips/Japan"}`, http.StatusBadRequest, slashMessage},
		{"rename root clash", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/rename", beach.ID), `{"name":"TRIPS"}`, http.StatusConflict, conflictMessage},
		{"rename nested clash", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/rename", nestedBeach.ID), `{"name":"japan"}`, http.StatusConflict, conflictMessage},
		{"rename to favorites at root", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/rename", beach.ID), `{"name":"favorites"}`, http.StatusConflict, conflictMessage},
		{"rename with slash", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/rename", beach.ID), `{"name":"a/b"}`, http.StatusBadRequest, slashMessage},
		{"move into a folder with a clashing name", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/move", rootJapan.ID), fmt.Sprintf(`{"parentId":%d}`, trips.ID), http.StatusConflict, conflictMessage},
		{"move to root with a clashing name", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/move", nestedBeach.ID), `{"parentId":null}`, http.StatusConflict, conflictMessage},
		{"move nested Favorites to root", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/move", nestedFavorites.ID), `{"parentId":null}`, http.StatusConflict, conflictMessage},
		{"rename to own name in another case", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/rename", japan.ID), `{"name":"JAPAN"}`, http.StatusOK, ""},
		{"create same name under another parent", http.MethodPost, "/api/v0/albums", fmt.Sprintf(`{"name":"Beach","parentId":%d}`, rootJapan.ID), http.StatusCreated, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := doAlbumReq(engine, tc.method, tc.path, tc.body)
			if w.Code != tc.wantCode {
				t.Fatalf("%s %s = %d, want %d: %s", tc.method, tc.path, w.Code, tc.wantCode, w.Body.String())
			}
			if tc.wantMessage == "" {
				return
			}
			var body struct {
				Error string `json:"error"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatalf("decode %s: %v", w.Body.String(), err)
			}
			if body.Error != tc.wantMessage {
				t.Errorf("error = %q, want %q", body.Error, tc.wantMessage)
			}
		})
	}

	if got, _ := q.GetAlbum(ctx, db.GetAlbumParams{ID: japan.ID, UserID: owner}); got.Name != "JAPAN" {
		t.Errorf("case-only rename did not apply: %q", got.Name)
	}
	if got, _ := q.GetAlbum(ctx, db.GetAlbumParams{ID: rootJapan.ID, UserID: owner}); got.ParentID.Valid {
		t.Errorf("clashing move applied: %+v", got)
	}
}

// --- Albums per account (HTTP) ---

// TestAlbums_PerUser checks albums belong to one account (#1912): two admins
// each own a root Trips and see only their own albums, and one gets 404 for
// every route on the other's album id and 400 for the other's album as a
// parent.
func TestAlbums_PerUser(t *testing.T) {
	database := dbtest.NewDB(t)
	q := database.Queries
	ctx := context.Background()
	ids := map[string]int64{}
	for _, name := range []string{"ann", "ben"} {
		user, err := q.CreateUser(ctx, db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		ids[name] = user.ID
	}
	deps := deputil.NewDependencies().WithDatabase(database)
	principal := accessutil.Principal{}
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), NewRouter())

	as := func(name string) { principal = accessutil.Principal{UserID: ids[name], IsAdmin: true} }
	create := func(body string) AlbumJSON {
		t.Helper()
		w := doAlbumReq(engine, http.MethodPost, "/api/v0/albums", body)
		var album AlbumJSON
		if err := json.Unmarshal(w.Body.Bytes(), &album); w.Code != http.StatusCreated || err != nil {
			t.Fatalf("create %s = %d %s: %v", body, w.Code, w.Body.String(), err)
		}
		return album
	}
	names := func() []string {
		t.Helper()
		w := doAlbumReq(engine, http.MethodGet, "/api/v0/albums", "")
		var albums []AlbumJSON
		if err := json.Unmarshal(w.Body.Bytes(), &albums); w.Code != http.StatusOK || err != nil {
			t.Fatalf("list = %d %s: %v", w.Code, w.Body.String(), err)
		}
		got := []string{}
		for _, a := range albums {
			got = append(got, a.Name)
		}
		slices.Sort(got)
		return got
	}

	as("ann")
	annTrips := create(`{"name":"Trips"}`)
	annJapan := create(fmt.Sprintf(`{"name":"Japan","parentId":%d}`, annTrips.ID))
	if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: annTrips.ID, RelPath: "a.jpg"}); err != nil {
		t.Fatal(err)
	}
	as("ben")
	benTrips := create(`{"name":"trips"}`)
	if got, want := names(), []string{"Favorites", "trips"}; !slices.Equal(got, want) {
		t.Errorf("ben's albums = %v, want %v", got, want)
	}

	annPath := fmt.Sprintf("/api/v0/albums/%d", annTrips.ID)
	photo := `{"deviceSerial":"","relPath":"a.jpg"}`
	cases := []struct {
		name, method, path, body string
		want                     int
	}{
		{"get", http.MethodGet, annPath, "", http.StatusNotFound},
		{"rename", http.MethodPatch, annPath + "/rename", `{"name":"Mine"}`, http.StatusNotFound},
		{"move", http.MethodPatch, annPath + "/move", `{"parentId":null}`, http.StatusNotFound},
		{"delete", http.MethodDelete, annPath, "", http.StatusNotFound},
		{"list items", http.MethodGet, annPath + "/items", "", http.StatusNotFound},
		{"add item", http.MethodPost, annPath + "/items", photo, http.StatusNotFound},
		{"remove item", http.MethodDelete, annPath + "/items", photo, http.StatusNotFound},
		{"create under", http.MethodPost, "/api/v0/albums", fmt.Sprintf(`{"name":"Child","parentId":%d}`, annTrips.ID), http.StatusBadRequest},
		{"move under", http.MethodPatch, fmt.Sprintf("/api/v0/albums/%d/move", benTrips.ID), fmt.Sprintf(`{"parentId":%d}`, annTrips.ID), http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w := doAlbumReq(engine, tc.method, tc.path, tc.body)
			if w.Code != tc.want {
				t.Fatalf("%s %s = %d, want %d: %s", tc.method, tc.path, w.Code, tc.want, w.Body.String())
			}
			if tc.want == http.StatusBadRequest && !strings.Contains(w.Body.String(), "parent album not found") {
				t.Errorf("%s %s error = %s, want parent album not found", tc.method, tc.path, w.Body.String())
			}
		})
	}

	as("ann")
	if got, want := names(), []string{"Favorites", "Japan", "Trips"}; !slices.Equal(got, want) {
		t.Errorf("ann's albums = %v, want %v", got, want)
	}
	if got, err := q.GetAlbum(ctx, db.GetAlbumParams{ID: annJapan.ID, UserID: ids["ann"]}); err != nil || got.ParentID.Int64 != annTrips.ID {
		t.Errorf("ann's Japan = %+v, %v; want it still under Trips", got, err)
	}
	if n, _ := q.CountAlbumItems(ctx, annTrips.ID); n != 1 {
		t.Errorf("ann's Trips holds %d items, want 1", n)
	}
	if got, err := q.GetAlbum(ctx, db.GetAlbumParams{ID: benTrips.ID, UserID: ids["ben"]}); err != nil || got.ParentID.Valid {
		t.Errorf("ben's trips = %+v, %v; want it still at the root", got, err)
	}
}
