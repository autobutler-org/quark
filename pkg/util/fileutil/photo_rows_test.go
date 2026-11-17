package fileutil

import (
	"context"
	"database/sql"
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
func photoOwner(t *testing.T, q db.Querier, username string) int64 {
	t.Helper()
	user, err := q.CreateUser(context.Background(), db.CreateUserParams{Username: username, PasswordHash: "h", RecoveryPhraseHash: "r"})
	if err != nil {
		t.Fatalf("CreateUser(%q): %v", username, err)
	}
	return user.ID
}

// favoriteKeys lists an account's favorites as "serial|path", sorted.
func favoriteKeys(t *testing.T, q db.Querier, userID int64) []string {
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
func albumKeys(t *testing.T, q db.Querier, albumID int64) []string {
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

func favorite(t *testing.T, q db.Querier, userID int64, serial, relPath string) {
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
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for _, p := range []string{"a.jpg", "trip/b.jpg", "trip/sub/c.jpg", "trips/d.jpg"} {
		if err := fsys.Write(ctx, p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, fsys); err != nil {
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

// TestMoveFileIntoItsOwnSubtreeLeavesPhotoRowsAlone: MoveFavorites and
// MoveAlbumItems skip a row whose destination is taken by reading the table
// they are updating, which is only well defined while the moved paths and
// their destinations do not overlap. They overlap when a folder moves into
// itself, and a device refuses that rename before any row is touched.
func TestMoveFileIntoItsOwnSubtreeLeavesPhotoRowsAlone(t *testing.T) {
	const serial = "USB-2957"
	mountPoint := t.TempDir()
	paths := []string{"trip/b.jpg", "trip/inner/b.jpg"}
	for _, p := range paths {
		full := filepath.Join(mountPoint, "quark", "data", "files", p)
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
	for _, p := range paths {
		favorite(t, q, owner, serial, p)
	}

	if _, err := MoveFile(MoveFileParams{
		Ctx: context.Background(), Registry: usbRegistry(t, mountPoint, serial), EventBus: eventbus.New(), Database: database,
		OldFilePath: "trip", NewFilePath: "trip/inner", OldDeviceSerial: serial, NewDeviceSerial: serial,
	}); err == nil {
		t.Fatal("MoveFile(trip, trip/inner) succeeded, want the rename refused")
	}
	want := []string{serial + "|trip/b.jpg", serial + "|trip/inner/b.jpg"}
	if got := favoriteKeys(t, q, owner); !reflect.DeepEqual(got, want) {
		t.Errorf("favorites = %v, want %v", got, want)
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
		Registry:  usbRegistry(t, mountPoint, serial),
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

// hashKeys lists every stored photo hash as "serial|path", sorted.
func hashKeys(t *testing.T, q db.Querier) []string {
	t.Helper()
	rows, err := q.ListNearDuplicates(context.Background())
	if err != nil {
		t.Fatalf("ListNearDuplicates: %v", err)
	}
	keys := []string{}
	for _, r := range rows {
		keys = append(keys, r.DeviceSerial+"|"+r.RelPath)
	}
	sort.Strings(keys)
	return keys
}

func hashPhoto(t *testing.T, q db.Querier, serial, relPath string) {
	t.Helper()
	if err := q.UpsertPhotoHash(context.Background(), db.UpsertPhotoHashParams{
		DeviceSerial: serial,
		RelPath:      relPath,
		Dhash:        sql.NullString{String: "0000000000000000", Valid: true},
	}); err != nil {
		t.Fatalf("UpsertPhotoHash(%q): %v", relPath, err)
	}
}

// TestMoveFileDropsPhotoHashes: a moved photo's hashes go with the old path,
// so the duplicates view never lists a path that is no longer there (#1666).
func TestMoveFileDropsPhotoHashes(t *testing.T) {
	ctx := context.Background()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for _, p := range []string{"a.jpg", "trip/b.jpg", "trips/c.jpg"} {
		if err := fsys.Write(ctx, p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, fsys); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	q := database.Queries
	for _, p := range []string{"a.jpg", "trip/b.jpg", "trips/c.jpg"} {
		hashPhoto(t, q, "", p)
	}

	for _, m := range [][2]string{{"a.jpg", "renamed.jpg"}, {"trip", "2024/trip"}} {
		if _, err := MoveFile(MoveFileParams{
			Ctx: ctx, Registry: registry, EventBus: eventbus.New(), Database: database,
			OldFilePath: m[0], NewFilePath: m[1],
		}); err != nil {
			t.Fatalf("MoveFile(%q, %q): %v", m[0], m[1], err)
		}
	}

	if got, want := hashKeys(t, q), []string{"|trips/c.jpg"}; !reflect.DeepEqual(got, want) {
		t.Errorf("hashes = %v, want %v", got, want)
	}
}

// TestDeleteFilesDropsPhotoHashes: a deleted photo, or a photo in a deleted
// folder, loses its hashes; its neighbors keep theirs (#1666).
func TestDeleteFilesDropsPhotoHashes(t *testing.T) {
	const serial = "USB-1666"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	paths := []string{"keep.jpg", "gone.jpg", "trip/b.jpg", "trips/d.jpg"}
	for _, p := range paths {
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
	for _, p := range paths {
		hashPhoto(t, q, serial, p)
	}
	hashPhoto(t, q, "", "gone.jpg") // same path, other device

	if _, err := DeleteFiles(DeleteFilesParams{
		Registry:  usbRegistry(t, mountPoint, serial),
		EventBus:  eventbus.New(),
		Database:  database,
		RootDir:   "/",
		FilePaths: []string{"gone.jpg", "trip"},
		Serial:    serial,
	}); err != nil {
		t.Fatalf("DeleteFiles: %v", err)
	}

	want := []string{"USB-1666|keep.jpg", "USB-1666|trips/d.jpg", "|gone.jpg"}
	sort.Strings(want)
	deadline := time.Now().Add(5 * time.Second)
	for !reflect.DeepEqual(hashKeys(t, q), want) && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if got := hashKeys(t, q); !reflect.DeepEqual(got, want) {
		t.Errorf("hashes = %v, want %v", got, want)
	}
}

// usbRegistry registers the namespace of a USB drive mounted at mountPoint,
// the way the server registers every device it finds.
func usbRegistry(t *testing.T, mountPoint, serial string) vfs.Registry {
	t.Helper()
	registry := vfs.NewRegistry()
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{
		Registry: registry,
		Storage:  storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: serial}),
	}); err != nil {
		t.Fatal(err)
	}
	return registry
}

// rotationOf is the saved rotation at a path, 0 when none is stored.
func rotationOf(t *testing.T, q db.Querier, serial, relPath string) int64 {
	t.Helper()
	quarters, err := q.GetPhotoRotation(context.Background(), db.GetPhotoRotationParams{DeviceSerial: serial, RelPath: relPath})
	if err == sql.ErrNoRows {
		return 0
	}
	if err != nil {
		t.Fatalf("GetPhotoRotation(%q, %q): %v", serial, relPath, err)
	}
	return quarters
}

func rotate(t *testing.T, q db.Querier, serial, relPath string, quarters int64) {
	t.Helper()
	if err := q.UpsertPhotoRotation(context.Background(), db.UpsertPhotoRotationParams{
		DeviceSerial: serial, RelPath: relPath, RotationQuarters: quarters,
	}); err != nil {
		t.Fatalf("UpsertPhotoRotation(%q): %v", relPath, err)
	}
}

// TestMoveFileCarriesPhotoRotation: a rotated photo stays rotated at its new
// path, whether it is renamed, moved inside a folder, or moved to another
// device (#4284). A rotation already stored at a replaced destination is the
// old file's and goes; a prefix-sharing sibling keeps its own.
func TestMoveFileCarriesPhotoRotation(t *testing.T) {
	const usb = "USB-4284"
	ctx := context.Background()
	internal := vfs.NewMemVFS(vfs.FilesNamespace(""))
	drive := vfs.NewMemVFS(vfs.FilesNamespace(usb))
	registry := vfs.NewRegistry()
	for serial, fsys := range map[string]vfs.VFS{"": internal, usb: drive} {
		if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	for _, p := range []string{"a.jpg", "b.jpg", "replaced.jpg", "trip/c.jpg", "trip/sub/d.jpg", "trips/e.jpg", "far.jpg"} {
		if err := internal.Write(ctx, p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	database := dbtest.NewDB(t)
	q := database.Queries
	rotate(t, q, "", "a.jpg", 1)
	rotate(t, q, "", "replaced.jpg", 3)
	rotate(t, q, "", "trip/c.jpg", 2)
	rotate(t, q, "", "trip/sub/d.jpg", 3)
	rotate(t, q, "", "trips/e.jpg", 1)
	rotate(t, q, "", "far.jpg", 2)

	for _, m := range []struct{ oldSerial, oldPath, newSerial, newPath string }{
		{"", "a.jpg", "", "renamed.jpg"},
		{"", "b.jpg", "", "replaced.jpg"}, // b has no rotation; replaced.jpg's goes with its old content
		{"", "/trip", "", "2024/trip"},
		{"", "far.jpg", usb, "moved/far.jpg"},
	} {
		if _, err := MoveFile(MoveFileParams{
			Ctx: ctx, Registry: registry, EventBus: eventbus.New(), Database: database,
			OldDeviceSerial: m.oldSerial, OldFilePath: m.oldPath, NewDeviceSerial: m.newSerial, NewFilePath: m.newPath,
		}); err != nil {
			t.Fatalf("MoveFile(%q, %q): %v", m.oldPath, m.newPath, err)
		}
	}

	for _, c := range []struct {
		serial, path string
		want         int64
	}{
		{"", "renamed.jpg", 1},
		{"", "a.jpg", 0},
		{"", "replaced.jpg", 0},
		{"", "2024/trip/c.jpg", 2},
		{"", "2024/trip/sub/d.jpg", 3},
		{"", "trip/c.jpg", 0},
		{"", "trip/sub/d.jpg", 0},
		{"", "trips/e.jpg", 1},
		{usb, "moved/far.jpg", 2},
		{"", "far.jpg", 0},
	} {
		if got := rotationOf(t, q, c.serial, c.path); got != c.want {
			t.Errorf("rotation of %q|%q = %d, want %d", c.serial, c.path, got, c.want)
		}
	}
}

// TestDeleteFilesForgetsPhotoRotation: a deleted photo, or a photo in a
// deleted folder, loses its saved rotation; a prefix-sharing sibling and the
// same path on another device keep theirs.
func TestDeleteFilesForgetsPhotoRotation(t *testing.T) {
	const serial = "USB-4284"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	paths := []string{"keep.jpg", "gone.jpg", "trip/b.jpg", "trip/sub/c.jpg", "trips/d.jpg"}
	for _, p := range paths {
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
	for _, p := range paths {
		rotate(t, q, serial, p, 1)
	}
	rotate(t, q, "", "gone.jpg", 2) // same path, other device

	if _, err := DeleteFiles(DeleteFilesParams{
		Registry:  usbRegistry(t, mountPoint, serial),
		EventBus:  eventbus.New(),
		Database:  database,
		RootDir:   "/",
		FilePaths: []string{"gone.jpg", "trip"},
		Serial:    serial,
	}); err != nil {
		t.Fatalf("DeleteFiles: %v", err)
	}

	rotations := func() []int64 {
		return []int64{
			rotationOf(t, q, serial, "keep.jpg"),
			rotationOf(t, q, serial, "trips/d.jpg"),
			rotationOf(t, q, "", "gone.jpg"),
			rotationOf(t, q, serial, "gone.jpg"),
			rotationOf(t, q, serial, "trip/b.jpg"),
			rotationOf(t, q, serial, "trip/sub/c.jpg"),
		}
	}
	want := []int64{1, 1, 2, 0, 0, 0}
	deadline := time.Now().Add(5 * time.Second)
	for !reflect.DeepEqual(rotations(), want) && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if got := rotations(); !reflect.DeepEqual(got, want) {
		t.Errorf("rotations (keep, trips/d, other device's gone, gone, trip/b, trip/sub/c) = %v, want %v", got, want)
	}
}
