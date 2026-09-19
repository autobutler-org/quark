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

// newUser creates an account to own favorites and albums.
func newUser(t *testing.T, q *db.Queries, username string) int64 {
	t.Helper()
	user, err := q.CreateUser(context.Background(), db.CreateUserParams{
		Username: username, PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatalf("CreateUser(%q): %v", username, err)
	}
	return user.ID
}

// TestEnsureFavoritesAlbum_CreatesOnFirstCall verifies that the Favorites
// system album is created when it doesn't yet exist.
func TestEnsureFavoritesAlbum_CreatesOnFirstCall(t *testing.T) {
	q := newTestDB(t)
	owner := newUser(t, q, "founder")
	album, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q, owner)
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
	owner := newUser(t, q, "founder")
	a1, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q, owner)
	if err != nil {
		t.Fatalf("first call: %v", err)
	}
	a2, err := favoritesutil.EnsureFavoritesAlbum(context.Background(), q, owner)
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
	owner := newUser(t, q, "founder")
	ctx := context.Background()
	if _, err := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "favorites"}); err != nil {
		t.Fatalf("CreateAlbum: %v", err)
	}
	if _, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner); !errors.Is(err, favoritesutil.ErrFavoritesNameTaken) {
		t.Fatalf("EnsureFavoritesAlbum error = %v, want ErrFavoritesNameTaken", err)
	}
	// The name is only taken in the owner's own root.
	if _, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, newUser(t, q, "other")); err != nil {
		t.Fatalf("EnsureFavoritesAlbum for another account: %v", err)
	}
}

// TestEnsureFavoritesAlbum_NestedNameDoesNotBlock verifies that only a root
// album clashes: Favorites nested under another album is a different sibling
// group.
func TestEnsureFavoritesAlbum_NestedNameDoesNotBlock(t *testing.T) {
	q := newTestDB(t)
	owner := newUser(t, q, "founder")
	ctx := context.Background()
	parent, err := q.CreateAlbum(ctx, db.CreateAlbumParams{UserID: owner, Name: "Trips"})
	if err != nil {
		t.Fatalf("CreateAlbum: %v", err)
	}
	if _, err := q.CreateAlbum(ctx, db.CreateAlbumParams{
		UserID:   owner,
		Name:     "Favorites",
		ParentID: sql.NullInt64{Int64: parent.ID, Valid: true},
	}); err != nil {
		t.Fatalf("CreateAlbum nested: %v", err)
	}
	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner)
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
	owner := newUser(t, q, "founder")
	ctx := context.Background()
	serial := "SN001"
	path := "photos/test.jpg"

	// First toggle: should add to favorites.
	isFav, err := favoritesutil.ToggleFavorite(ctx, q, owner, serial, path)
	if err != nil {
		t.Fatalf("first toggle: %v", err)
	}
	if !isFav {
		t.Error("expected isFav=true after first toggle")
	}

	// Second toggle: should remove from favorites.
	isFav, err = favoritesutil.ToggleFavorite(ctx, q, owner, serial, path)
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
	owner := newUser(t, q, "founder")
	ctx := context.Background()
	serial := ""
	path := "docs/note.txt"

	// Ensure the album exists first.
	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}

	// Toggle to favorite.
	if _, err := favoritesutil.ToggleFavorite(ctx, q, owner, serial, path); err != nil {
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
	owner := newUser(t, q, "founder")
	ctx := context.Background()
	serial := "SN002"
	path := "pics/sunset.jpg"

	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner)
	if err != nil {
		t.Fatalf("EnsureFavoritesAlbum: %v", err)
	}

	// Add then remove.
	if _, err := favoritesutil.ToggleFavorite(ctx, q, owner, serial, path); err != nil {
		t.Fatalf("first toggle (add): %v", err)
	}
	if _, err := favoritesutil.ToggleFavorite(ctx, q, owner, serial, path); err != nil {
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
	owner := newUser(t, q, "founder")
	ctx := context.Background()

	photos := []string{"a.jpg", "b.jpg", "c.jpg"}
	for _, p := range photos {
		if _, err := favoritesutil.ToggleFavorite(ctx, q, owner, "", p); err != nil {
			t.Fatalf("ToggleFavorite(%q): %v", p, err)
		}
	}

	album, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner)
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
	owner := newUser(t, q, "founder")
	ctx := context.Background()
	path := "internal/photo.jpg"

	// Empty serial and named serial should be independent favorites entries.
	isFav1, err := favoritesutil.ToggleFavorite(ctx, q, owner, "", path)
	if err != nil {
		t.Fatalf("toggle with empty serial: %v", err)
	}
	isFav2, err := favoritesutil.ToggleFavorite(ctx, q, owner, "EXT001", path)
	if err != nil {
		t.Fatalf("toggle with named serial: %v", err)
	}
	if !isFav1 || !isFav2 {
		t.Errorf("both should be favorited: empty=%v ext=%v", isFav1, isFav2)
	}
}

// TestToggleFavorite_PerUser verifies two accounts favorite the same photo
// independently, each into its own Favorites album, and that deleting an
// account deletes its favorites and album but not the other's (#1912).
func TestToggleFavorite_PerUser(t *testing.T) {
	q := newTestDB(t)
	ctx := context.Background()
	ann := newUser(t, q, "ann")
	ben := newUser(t, q, "ben")
	for _, user := range []int64{ann, ben} {
		if on, err := favoritesutil.ToggleFavorite(ctx, q, user, "", "beach.jpg"); err != nil || !on {
			t.Fatalf("ToggleFavorite(%d) = %v, %v; want true", user, on, err)
		}
	}
	if on, err := favoritesutil.ToggleFavorite(ctx, q, ann, "", "beach.jpg"); err != nil || on {
		t.Fatalf("second ToggleFavorite(ann) = %v, %v; want false", on, err)
	}
	if fav, err := q.IsFavorite(ctx, db.IsFavoriteParams{UserID: ben, RelPath: "beach.jpg"}); err != nil || !fav {
		t.Errorf("ben's favorite after ann removed hers = %v, %v; want true", fav, err)
	}

	annAlbum, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, ann)
	if err != nil {
		t.Fatal(err)
	}
	benAlbum, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, ben)
	if err != nil {
		t.Fatal(err)
	}
	if annAlbum.ID == benAlbum.ID {
		t.Fatalf("ann and ben share Favorites album %d", annAlbum.ID)
	}
	if n, _ := q.CountAlbumItems(ctx, annAlbum.ID); n != 0 {
		t.Errorf("ann's Favorites album holds %d items, want 0", n)
	}
	if n, _ := q.CountAlbumItems(ctx, benAlbum.ID); n != 1 {
		t.Errorf("ben's Favorites album holds %d items, want 1", n)
	}

	if err := q.DeleteUser(ctx, ben); err != nil {
		t.Fatal(err)
	}
	if rows, err := q.ListFavorites(ctx, ben); err != nil || len(rows) != 0 {
		t.Errorf("ben's favorites after deleting ben = %v, %v; want none", rows, err)
	}
	if _, err := q.GetAlbum(ctx, db.GetAlbumParams{ID: benAlbum.ID, UserID: ben}); !errors.Is(err, sql.ErrNoRows) {
		t.Errorf("ben's Favorites album after deleting ben: %v, want sql.ErrNoRows", err)
	}
	if _, err := q.GetAlbum(ctx, db.GetAlbumParams{ID: annAlbum.ID, UserID: ann}); err != nil {
		t.Errorf("ann's Favorites album after deleting ben: %v", err)
	}
}
