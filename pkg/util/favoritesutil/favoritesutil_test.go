package favoritesutil_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	_ "modernc.org/sqlite"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
)

// newTestDB returns queries over a database carrying the real migration set.
func newTestDB(t *testing.T) *db.Queries {
	t.Helper()
	return dbtest.NewDB(t).Queries
}

// TestEnsureFavoritesAlbum_CreatesOnFirstCall verifies that the Favorites
// system album is created when it doesn't yet exist.
func TestEnsureFavoritesAlbum_CreatesOnFirstCall(t *testing.T) {
	q := newTestDB(t)
	album, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	if album.ID == 0 {
		t.Error("expected non-zero album ID")
	}
	if album.Name == "" {
		t.Error("expected non-empty album name")
	}
}

// TestEnsureFavoritesAlbum_Idempotent verifies that calling EnsureFavoritesAlbum
// twice returns the same album, not a duplicate.
func TestEnsureFavoritesAlbum_Idempotent(t *testing.T) {
	q := newTestDB(t)
	a1, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q)
	if err != nil {
		t.Fatalf("first call: %v", err)
	}
	a2, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q)
	if err != nil {
		t.Fatalf("second call: %v", err)
	}
	if a1.ID != a2.ID {
		t.Errorf("expected same album ID on both calls: got %d and %d", a1.ID, a2.ID)
	}
}

// TestEnsureFavoritesAlbum_UserAlbumHoldsName verifies that a user album at
// the root holding the name is reported as such rather than mistaken for a
// creation race. The raw query bypasses albumutil, which would refuse it.
func TestEnsureFavoritesAlbum_UserAlbumHoldsName(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	if _, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "favorites"}); err != nil {
		t.Fatalf("CreateAlbum: %v", err)
	}
	if _, err := favoritesutil.EnsureFavoritesAlbum(ctx, q); !errors.Is(err, favoritesutil.ErrFavoritesNameTaken) {
		t.Fatalf("EnsureFavoritesAlbum error = %v, want ErrFavoritesNameTaken", err)
	}
}

// TestEnsureFavoritesAlbum_NestedNameDoesNotBlock verifies that only a root
// album clashes: Favorites nested under another album is a different sibling
// group.
func TestEnsureFavoritesAlbum_NestedNameDoesNotBlock(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	parent, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Trips"})
	if err != nil {
		t.Fatalf("CreateAlbum: %v", err)
	}
	if _, err := q.CreateAlbum(ctx, db.CreateAlbumParams{
		Name:     "Favorites",
		ParentID: sql.NullInt64{Int64: parent.ID, Valid: true},
	}); err != nil {
		t.Fatalf("CreateAlbum nested: %v", err)
	}
	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	if !album.SmartType.Valid || album.ParentID.Valid {
		t.Errorf("got %+v, want the root system album", album)
	}
}

// TestToggleFavorite_AddsThenRemoves verifies the basic toggle cycle:
// unfavorited → favorited → unfavorited.
func TestToggleFavorite_AddsThenRemoves(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	serial := "SN001"
	path := "photos/test.jpg"

	// First toggle: should add to favorites.
	isFav, err := favoritesutil.ToggleFavorite(ctx, q, serial, path)
	if err != nil {
		t.Fatalf("first toggle: %v", err)
	}
	if !isFav {
		t.Error("expected isFav=true after first toggle")
	}

	// Second toggle: should remove from favorites.
	isFav, err = favoritesutil.ToggleFavorite(ctx, q, serial, path)
	if err != nil {
		t.Fatalf("second toggle: %v", err)
	}
	if isFav {
		t.Error("expected isFav=false after second toggle")
	}
}

// TestToggleFavorite_SyncsAlbum verifies that toggling a favorite also
// adds the photo to the Favorites smart album.
func TestToggleFavorite_SyncsAlbum(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	serial := ""
	path := "docs/note.txt"

	// Ensure the album exists first.
	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}

	// Toggle to favorite.
	if _, err := favoritesutil.ToggleFavorite(ctx, q, serial, path); err != nil {
		t.Fatalf("ToggleFavorite: %v", err)
	}

	// The photo should now be in the album.
	items, err := q.ListAlbumItems(ctx, album.ID)
	if err != nil {
		t.Fatalf("ListAlbumItems: %v", err)
	}
	found := false
	for _, item := range items {
		if item.RelPath == path {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected %q in Favorites album after toggle, items: %v", path, items)
	}
}

// TestToggleFavorite_RemovesSyncsAlbum verifies that un-favoriting also
// removes the photo from the Favorites album.
func TestToggleFavorite_RemovesSyncsAlbum(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	serial := "SN002"
	path := "pics/sunset.jpg"

	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}

	// Add then remove.
	if _, err := favoritesutil.ToggleFavorite(ctx, q, serial, path); err != nil {
		t.Fatalf("first toggle (add): %v", err)
	}
	if _, err := favoritesutil.ToggleFavorite(ctx, q, serial, path); err != nil {
		t.Fatalf("second toggle (remove): %v", err)
	}

	// Album should be empty now.
	items, err := q.ListAlbumItems(ctx, album.ID)
	if err != nil {
		t.Fatalf("ListAlbumItems: %v", err)
	}
	if len(items) != 0 {
		t.Errorf("expected empty album after un-favorite, got %d items", len(items))
	}
}

// TestToggleFavorite_MultiplePhotos verifies that multiple independent photos
// can be favorited without interfering with each other.
func TestToggleFavorite_MultiplePhotos(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()

	photos := []string{"a.jpg", "b.jpg", "c.jpg"}
	for _, p := range photos {
		if _, err := favoritesutil.ToggleFavorite(ctx, q, "", p); err != nil {
			t.Fatalf("ToggleFavorite(%q): %v", p, err)
		}
	}

	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}
	items, err := q.ListAlbumItems(ctx, album.ID)
	if err != nil {
		t.Fatalf("ListAlbumItems: %v", err)
	}
	if len(items) != len(photos) {
		t.Errorf("expected %d items in Favorites album, got %d", len(photos), len(items))
	}
}

// TestToggleFavorite_EmptySerialIsValid verifies that an empty device serial
// (internal storage) is a valid key and doesn't conflict with named serials.
func TestToggleFavorite_EmptySerialIsValid(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	path := "internal/photo.jpg"

	// Empty serial and named serial should be independent favorites entries.
	isFav1, err := favoritesutil.ToggleFavorite(ctx, q, "", path)
	if err != nil {
		t.Fatalf("toggle with empty serial: %v", err)
	}
	isFav2, err := favoritesutil.ToggleFavorite(ctx, q, "EXT001", path)
	if err != nil {
		t.Fatalf("toggle with named serial: %v", err)
	}
	if !isFav1 || !isFav2 {
		t.Errorf("both should be favorited: empty=%v ext=%v", isFav1, isFav2)
	}
}
