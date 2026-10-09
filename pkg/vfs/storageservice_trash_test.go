package vfs_test

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// trasherOn returns the Trasher of the namespace serial names in registry.
func trasherOn(t *testing.T, registry vfs.Registry, serial string) (vfs.VFS, vfs.Trasher) {
	t.Helper()
	fsys, ok := registry.Get(vfs.FilesNamespace(serial))
	if !ok {
		t.Fatalf("no namespace for serial %q", serial)
	}
	trasher, ok := fsys.(vfs.Trasher)
	if !ok {
		t.Fatalf("%T is not a vfs.Trasher", fsys)
	}
	return fsys, trasher
}

// TestStorageServiceTrashRoundTrip trashes, lists, reads, restores and deletes
// on a device namespace, and checks each lands in that device's trash, beside
// its files directory, and nowhere else (#2641).
func TestStorageServiceTrashRoundTrip(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	svc := storageutil.NewStorageService(newDevicesDetector(internal.device(""), usb.device("A")))
	registry := newDeviceRegistry(t, svc)
	fsys, trasher := trasherOn(t, registry, "A")
	ctx := context.Background()

	writeOnDisk(t, usb.filesDir, "docs/notes.txt", "notes")
	writeOnDisk(t, usb.filesDir, "album/2024/one.jpg", "one")
	writeOnDisk(t, internal.filesDir, "docs/notes.txt", "internal")

	trashed, err := trasher.Trash(ctx, []string{"notes.txt", "missing.txt"}, vfs.TrashOptions{RootDir: "docs", TrashedBy: 7})
	if err != nil {
		t.Fatal(err)
	}
	if len(trashed) != 1 || trashed[0].OriginalPath != "docs/notes.txt" {
		t.Fatalf("trashed = %+v, want docs/notes.txt alone", trashed)
	}
	if _, err := trasher.Trash(ctx, []string{"album"}, vfs.TrashOptions{}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(usb.filesDir, "docs", "notes.txt")); !os.IsNotExist(err) {
		t.Errorf("the trashed file is still in place: %v", err)
	}
	if _, err := os.Stat(filepath.Join(internal.filesDir, "docs", "notes.txt")); err != nil {
		t.Errorf("trashing on A touched the internal drive: %v", err)
	}
	if _, err := os.Stat(filepath.Join(storageutil.TrashRoot(usb.filesDir), trashed[0].TrashName)); err != nil {
		t.Errorf("the item is not in A's trash: %v", err)
	}

	items, err := trasher.ListTrash(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Fatalf("ListTrash = %+v, want two items", items)
	}
	entry, err := trasher.ReadTrashEntry(ctx, trashed[0].TrashName)
	if err != nil {
		t.Fatal(err)
	}
	if entry.OriginalPath != "docs/notes.txt" || entry.TrashedBy != 7 {
		t.Errorf("entry = %+v, want docs/notes.txt trashed by 7", entry)
	}

	// The trashed item keeps its address in the namespace's path space.
	trashPath := storageutil.TrashPath(trashed[0].TrashName, "")
	info, err := fsys.Stat(ctx, trashPath)
	if err != nil {
		t.Fatalf("Stat(%s): %v", trashPath, err)
	}
	if info.IsDir || info.Size != int64(len("notes")) {
		t.Errorf("Stat(%s) = %+v", trashPath, info)
	}
	f, err := fsys.Open(ctx, trashPath)
	if err != nil {
		t.Fatalf("Open(%s): %v", trashPath, err)
	}
	body, err := io.ReadAll(f)
	_ = f.Close()
	if err != nil || string(body) != "notes" {
		t.Errorf("Open(%s) read %q, %v", trashPath, body, err)
	}

	album := ""
	for _, item := range items {
		if item.OriginalPath == "album" {
			album = item.TrashName
		}
	}
	contents, err := trasher.ListTrashContents(ctx, vfs.TrashRef{TrashName: album, Path: "2024"})
	if err != nil {
		t.Fatal(err)
	}
	if len(contents.Items) != 1 || contents.Items[0].Path != "2024/one.jpg" || contents.OriginalPath != "album/2024" {
		t.Errorf("contents = %+v", contents)
	}

	restored, err := trasher.RestoreTrash(ctx, []vfs.TrashRef{{TrashName: trashed[0].TrashName}})
	if err != nil {
		t.Fatal(err)
	}
	if len(restored) != 1 || restored[0].Path != "docs/notes.txt" {
		t.Errorf("restored = %+v", restored)
	}
	if _, err := os.Stat(filepath.Join(usb.filesDir, "docs", "notes.txt")); err != nil {
		t.Errorf("the restored file is not back: %v", err)
	}

	removed, err := trasher.DeleteTrash(ctx, []vfs.TrashRef{{TrashName: album, Path: "2024/one.jpg"}})
	if err != nil {
		t.Fatal(err)
	}
	if want := storageutil.TrashPath(album, "2024/one.jpg"); len(removed) != 1 || removed[0] != want {
		t.Errorf("DeleteTrash removed %v, want [%s]", removed, want)
	}
	removed, err = trasher.EmptyTrash(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(removed) != 1 {
		t.Errorf("EmptyTrash removed %v, want the album alone", removed)
	}
}

// TestStorageServicePurgeExpiredTrash deletes only what has outlived the
// retention period.
func TestStorageServicePurgeExpiredTrash(t *testing.T) {
	internal := newDeviceMount(t)
	svc := storageutil.NewStorageService(newDevicesDetector(internal.device("")))
	_, trasher := trasherOn(t, newDeviceRegistry(t, svc), "")
	ctx := context.Background()
	writeOnDisk(t, internal.filesDir, "a.txt", "a")
	if _, err := trasher.Trash(ctx, []string{"a.txt"}, vfs.TrashOptions{}); err != nil {
		t.Fatal(err)
	}

	removed, err := trasher.PurgeExpiredTrash(ctx, time.Now())
	if err != nil || len(removed) != 0 {
		t.Fatalf("a fresh item was purged: %v, %v", removed, err)
	}
	later := time.Now().AddDate(0, 0, storageutil.TrashRetentionDays+1)
	removed, err = trasher.PurgeExpiredTrash(ctx, later)
	if err != nil || len(removed) != 1 || !strings.HasPrefix(removed[0], ".trash/") {
		t.Fatalf("PurgeExpiredTrash after the retention period = %v, %v", removed, err)
	}
}

// TestStorageServiceTrashMovesTheOldHiddenTrash checks a pre-#2173 trash,
// <filesDir>/.trash, still moves out the first time the namespace's trash is
// used.
func TestStorageServiceTrashMovesTheOldHiddenTrash(t *testing.T) {
	internal := newDeviceMount(t)
	svc := storageutil.NewStorageService(newDevicesDetector(internal.device("")))
	_, trasher := trasherOn(t, newDeviceRegistry(t, svc), "")
	writeOnDisk(t, internal.filesDir, ".trash/20240101T000000Z_00_old.txt", "old")

	items, err := trasher.ListTrash(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].TrashName != "20240101T000000Z_00_old.txt" {
		t.Fatalf("ListTrash = %+v, want the old item", items)
	}
	if _, err := os.Stat(filepath.Join(internal.filesDir, ".trash")); !os.IsNotExist(err) {
		t.Errorf("the old hidden trash is still there: %v", err)
	}
}

// TestStorageServiceTrashPathIsReadOnly checks the trash changes only through
// Trasher: writing, deleting or escaping through a .trash/ path is refused.
func TestStorageServiceTrashPathIsReadOnly(t *testing.T) {
	internal := newDeviceMount(t)
	svc := storageutil.NewStorageService(newDevicesDetector(internal.device("")))
	fsys, trasher := trasherOn(t, newDeviceRegistry(t, svc), "")
	ctx := context.Background()
	writeOnDisk(t, internal.filesDir, "a.txt", "a")
	trashed, err := trasher.Trash(ctx, []string{"a.txt"}, vfs.TrashOptions{})
	if err != nil {
		t.Fatal(err)
	}
	trashPath := storageutil.TrashPath(trashed[0].TrashName, "")

	if err := fsys.Write(ctx, ".trash/planted.txt", strings.NewReader("x"), vfs.WriteOptions{}); !errors.Is(err, vfs.ErrPermissionDenied) {
		t.Errorf("Write into the trash = %v, want ErrPermissionDenied", err)
	}
	if err := fsys.Delete(ctx, trashPath, vfs.DeleteOptions{}); !errors.Is(err, vfs.ErrPermissionDenied) {
		t.Errorf("Delete in the trash = %v, want ErrPermissionDenied", err)
	}
	if _, err := fsys.Stat(ctx, ".trash/../../tmp"); err == nil {
		t.Error("Stat climbed out of the trash")
	}
	if _, err := fsys.Stat(ctx, ".trash/nothing-here"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("Stat of a missing trash item = %v, want ErrNotFound", err)
	}
}

// TestStorageServiceTrashOfAGoneDevice checks a namespace whose device was
// unplugged answers the error the trash has always given an unknown device,
// rather than reaching the internal drive's trash.
func TestStorageServiceTrashOfAGoneDevice(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	detector := newDevicesDetector(internal.device(""), usb.device("A"))
	svc := storageutil.NewStorageService(detector)
	registry := vfs.NewRegistry()
	stale := vfs.NewDeviceStorageServiceVFS(svc, "A")
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("A")}, stale); err != nil {
		t.Fatal(err)
	}
	writeOnDisk(t, internal.filesDir, "a.txt", "a")
	detector.set(internal.device(""))
	svc.InvalidateDeviceCache()

	_, err := stale.Trash(context.Background(), []string{"a.txt"}, vfs.TrashOptions{})
	if !errors.Is(err, vfs.ErrNotFound) || !errors.Is(err, storageutil.ErrDeviceNotFound) {
		t.Fatalf("Trash on a gone device = %v, want ErrNotFound and ErrDeviceNotFound", err)
	}
	if _, err := os.Stat(filepath.Join(internal.filesDir, "a.txt")); err != nil {
		t.Errorf("the internal drive's file moved: %v", err)
	}
}

func TestFilesNamespaceSerial(t *testing.T) {
	for _, tc := range []struct {
		id     string
		serial string
		ok     bool
	}{
		{"files", "", true},
		{"files:ABC", "ABC", true},
		{"files:", "", false},
		{"photos", "", false},
	} {
		serial, ok := vfs.FilesNamespaceSerial(tc.id)
		if serial != tc.serial || ok != tc.ok {
			t.Errorf("FilesNamespaceSerial(%q) = %q, %v; want %q, %v", tc.id, serial, ok, tc.serial, tc.ok)
		}
	}
}
