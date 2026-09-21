package fileutil

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/favoritesutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// photoOwner creates an account to own favorites and albums.
func photoOwner(t *testing.T, q *db.Queries, username string) int64 {
	t.Helper()
	user, err := q.CreateUser(context.Background(), db.CreateUserParams{Username: username, PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser(%q): %v", username, err)
	}
	return user.ID
}

// favoriteKeys lists an account's favorites as "serial|path", sorted.
func favoriteKeys(t *testing.T, q *db.Queries, userID int64) []string {
	t.Helper()
	rows, err := q.ListFavorites(context.Background(), userID)
	if err != nil {
		t.Fatalf("ListFavorites: %v", err)
	}
	keys := []string{}
	for _, r := range rows {
		keys = append(keys, r.DeviceSerial+"|"+r.RelPath)
	}
	sort.Strings(keys)
	return keys
}

// albumKeys lists an album's items as "serial|path", sorted.
func albumKeys(t *testing.T, q *db.Queries, albumID int64) []string {
	t.Helper()
	rows, err := q.ListAlbumItems(context.Background(), albumID)
	if err != nil {
		t.Fatalf("ListAlbumItems: %v", err)
	}
	keys := []string{}
	for _, r := range rows {
		keys = append(keys, r.DeviceSerial+"|"+r.RelPath)
	}
	sort.Strings(keys)
	return keys
}

func favorite(t *testing.T, q *db.Queries, userID int64, serial, relPath string) {
	t.Helper()
	if _, err := favoritesutil.ToggleFavorite(context.Background(), q, userID, serial, relPath); err != nil {
		t.Fatalf("ToggleFavorite(%q): %v", relPath, err)
	}
}

// TestMoveFileCarriesFavoritesAndAlbumItems moves a file and a folder and
// checks that favorites and album membership follow, including a destination
// that already had rows and a sibling folder sharing the moved folder's prefix.
func TestMoveFileCarriesFavoritesAndAlbumItems(t *testing.T) {
	ctx := context.Background()
	fsys := vfs.NewMemVFS(filesNamespace)
	for _, p := range []string{"a.jpg", "trip/b.jpg", "trip/sub/c.jpg", "trips/d.jpg"} {
		if err := fsys.Write(ctx, p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: filesNamespace}, fsys); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	q := database.Queries
	owner := photoOwner(t, q, "founder")

	for _, p := range []string{"a.jpg", "trip/b.jpg", "trip/sub/c.jpg", "trips/d.jpg"} {
		favorite(t, q, owner, "", p)
	}
	// A stale row already sitting at a destination must not block the move.
	favorite(t, q, owner, "", "2024/trip/b.jpg")
	// Moves are keyed by path, so another account's favorite follows too.
	other := photoOwner(t, q, "other")
	favorite(t, q, other, "", "trip/sub/c.jpg")
	user, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Trips", UserID: owner})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"trip/b.jpg", "2024/trip/b.jpg"} {
		if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: user.ID, RelPath: p}); err != nil {
			t.Fatal(err)
		}
	}

	move := func(oldPath, newPath string) {
		t.Helper()
		if _, err := MoveFile(MoveFileParams{
			Ctx: ctx, Registry: registry, EventBus: eventbus.New(), Database: database,
			OldFilePath: oldPath, NewFilePath: newPath,
		}); err != nil {
			t.Fatalf("MoveFile(%q, %q): %v", oldPath, newPath, err)
		}
	}
	move("a.jpg", "renamed.jpg")
	move("/trip", "2024/trip") // the file routes accept a leading slash

	want := []string{"|2024/trip/b.jpg", "|2024/trip/sub/c.jpg", "|renamed.jpg", "|trips/d.jpg"}
	if got := favoriteKeys(t, q, owner); !reflect.DeepEqual(got, want) {
		t.Errorf("favorites = %v, want %v", got, want)
	}
	if got, want := favoriteKeys(t, q, other), []string{"|2024/trip/sub/c.jpg"}; !reflect.DeepEqual(got, want) {
		t.Errorf("other account's favorites = %v, want %v", got, want)
	}
	fav, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner)
	if err != nil {
		t.Fatal(err)
	}
	if got := albumKeys(t, q, fav.ID); !reflect.DeepEqual(got, want) {
		t.Errorf("Favorites album = %v, want %v", got, want)
	}
	if got, want := albumKeys(t, q, user.ID), []string{"|2024/trip/b.jpg"}; !reflect.DeepEqual(got, want) {
		t.Errorf("user album = %v, want %v", got, want)
	}
}

// TestDeleteFilesForgetsFavoritesAndAlbumItems deletes a file and a folder and
// waits for the background cleanup to drop their favorites and album rows,
// leaving a prefix-sharing sibling and another device's same path alone.
func TestDeleteFilesForgetsFavoritesAndAlbumItems(t *testing.T) {
	const serial = "USB-992"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	for _, p := range []string{"keep.jpg", "gone.jpg", "trip/b.jpg", "trip/sub/c.jpg", "trips/d.jpg"} {
		full := filepath.Join(filesDir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	database := dbtest.NewDB(t)
	q := database.Queries
	owner := photoOwner(t, q, "founder")
	ctx := context.Background()

	for _, p := range []string{"keep.jpg", "gone.jpg", "trip/b.jpg", "trip/sub/c.jpg", "trips/d.jpg"} {
		favorite(t, q, owner, serial, p)
	}
	favorite(t, q, owner, "", "gone.jpg") // same path, other device
	user, err := q.CreateAlbum(ctx, db.CreateAlbumParams{Name: "Trips", UserID: owner})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := q.AddPhotoToAlbum(ctx, db.AddPhotoToAlbumParams{AlbumID: user.ID, DeviceSerial: serial, RelPath: "trip/sub/c.jpg"}); err != nil {
		t.Fatal(err)
	}

	if _, err := DeleteFiles(DeleteFilesParams{
		Storage:   storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: serial}),
		EventBus:  eventbus.New(),
		Database:  database,
		RootDir:   "/",
		FilePaths: []string{"gone.jpg", "trip"},
		Serial:    serial,
	}); err != nil {
		t.Fatalf("DeleteFiles: %v", err)
	}

	want := []string{"USB-992|keep.jpg", "USB-992|trips/d.jpg", "|gone.jpg"}
	sort.Strings(want)
	deadline := time.Now().Add(5 * time.Second)
	for !reflect.DeepEqual(favoriteKeys(t, q, owner), want) && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if got := favoriteKeys(t, q, owner); !reflect.DeepEqual(got, want) {
		t.Fatalf("favorites = %v, want %v", got, want)
	}
	// Album cleanup runs just before the favorites cleanup, so it is done too.
	fav, err := favoritesutil.EnsureFavoritesAlbum(ctx, q, owner)
	if err != nil {
		t.Fatal(err)
	}
	if got := albumKeys(t, q, fav.ID); !reflect.DeepEqual(got, want) {
		t.Errorf("Favorites album = %v, want %v", got, want)
	}
	if got := albumKeys(t, q, user.ID); len(got) != 0 {
		t.Errorf("user album = %v, want empty", got)
	}
}
