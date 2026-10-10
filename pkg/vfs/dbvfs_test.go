package vfs_test

import (
	"context"
	"io"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/vfs"
)

func newDBVFS(t *testing.T, ns string) *vfs.DBVFS {
	t.Helper()
	db := newTestDB(t)
	return vfs.NewDBVFS(db, ns)
}

func TestDBVFS_MkdirAllAndList(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.MkdirAll(ctx, "/albums/summer-2024/"); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}

	// List root — should see /albums/.
	entries, err := v.List(ctx, "/", nil)
	if err != nil {
		t.Fatalf("List /: %v", err)
	}
	if len(entries) != 1 || entries[0].Path != "albums" {
		t.Fatalf("expected [albums], got %v", entries)
	}
	if !entries[0].IsDir {
		t.Fatalf("expected albums to be a dir")
	}

	// List /albums/ — should see /albums/summer-2024/.
	entries, err = v.List(ctx, "/albums/", nil)
	if err != nil {
		t.Fatalf("List /albums/: %v", err)
	}
	if len(entries) != 1 || entries[0].Path != "albums/summer-2024" {
		t.Fatalf("expected [albums/summer-2024], got %v", entries)
	}
}

func TestDBVFS_ListRecursive(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.MkdirAll(ctx, "/albums/trip/sub/"); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}

	entries, err := v.List(ctx, "/albums/", &vfs.ListFilter{Recursive: true})
	if err != nil {
		t.Fatalf("List recursive: %v", err)
	}
	// Should include /albums/trip/ and /albums/trip/sub/
	if len(entries) < 2 {
		t.Fatalf("expected >= 2 entries, got %d: %v", len(entries), entries)
	}
}

func TestDBVFS_WriteStatOpen(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.MkdirAll(ctx, "/albums/"); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}

	content := "hello, DBVFS"
	if err := v.Write(ctx, "/albums/note.txt", strings.NewReader(content), vfs.WriteOptions{
		ContentType: "text/plain",
	}); err != nil {
		t.Fatalf("Write: %v", err)
	}

	fi, err := v.Stat(ctx, "/albums/note.txt")
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if fi.Size != int64(len(content)) {
		t.Fatalf("size: got %d, want %d", fi.Size, len(content))
	}
	if fi.IsDir {
		t.Fatal("expected file, not dir")
	}
	if fi.MimeType != "text/plain" {
		t.Fatalf("mime: got %q, want text/plain", fi.MimeType)
	}

	rc, err := v.Open(ctx, "/albums/note.txt")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer rc.Close()
	got, err := io.ReadAll(rc)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if string(got) != content {
		t.Fatalf("content: got %q, want %q", got, content)
	}
}

func TestDBVFS_StatNotFound(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	_, err := v.Stat(ctx, "/nope/missing")
	if err != vfs.ErrNotFound {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

func TestDBVFS_OpenDirectory(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.MkdirAll(ctx, "/albums/"); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}

	_, err := v.Open(ctx, "/albums/")
	if err != vfs.ErrIsDirectory {
		t.Fatalf("expected ErrIsDirectory opening dir, got %v", err)
	}
}

func TestDBVFS_WriteIfNoneMatchConflict(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.Write(ctx, "/file.bin", strings.NewReader("data"), vfs.WriteOptions{
		IfNoneMatch: "*",
	}); err != nil {
		t.Fatalf("first Write: %v", err)
	}

	err := v.Write(ctx, "/file.bin", strings.NewReader("data2"), vfs.WriteOptions{
		IfNoneMatch: "*",
	})
	if err != vfs.ErrConflict {
		t.Fatalf("expected ErrConflict, got %v", err)
	}
}

func TestDBVFS_DeleteFile(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.Write(ctx, "/tmp.txt", strings.NewReader("bye"), vfs.WriteOptions{}); err != nil {
		t.Fatalf("Write: %v", err)
	}

	if err := v.Delete(ctx, "/tmp.txt", vfs.DeleteOptions{}); err != nil {
		t.Fatalf("Delete: %v", err)
	}

	_, err := v.Stat(ctx, "/tmp.txt")
	if err != vfs.ErrNotFound {
		t.Fatalf("expected ErrNotFound after delete, got %v", err)
	}
}

func TestDBVFS_DeleteNonEmptyDir(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.MkdirAll(ctx, "/albums/"); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := v.Write(ctx, "/albums/photo.jpg", strings.NewReader("img"), vfs.WriteOptions{}); err != nil {
		t.Fatalf("Write: %v", err)
	}

	err := v.Delete(ctx, "/albums/", vfs.DeleteOptions{Recursive: false})
	if err != vfs.ErrNotEmpty {
		t.Fatalf("expected ErrNotEmpty, got %v", err)
	}
}

func TestDBVFS_DeleteRecursive(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	if err := v.MkdirAll(ctx, "/albums/trip/"); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := v.Write(ctx, "/albums/trip/photo.jpg", strings.NewReader("img"), vfs.WriteOptions{}); err != nil {
		t.Fatalf("Write: %v", err)
	}

	if err := v.Delete(ctx, "/albums/", vfs.DeleteOptions{Recursive: true}); err != nil {
		t.Fatalf("Delete recursive: %v", err)
	}

	// All entries under /albums/ should be gone.
	entries, err := v.List(ctx, "/", nil)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Path, "albums/") || e.Path == "albums" {
			t.Fatalf("entry %q should have been deleted", e.Path)
		}
	}
}

func TestDBVFS_WatchNotSupported(t *testing.T) {
	v := newDBVFS(t, "photos")
	ctx := context.Background()

	_, err := v.Watch(ctx, "/")
	if err != vfs.ErrWatchNotSupported {
		t.Fatalf("expected ErrWatchNotSupported, got %v", err)
	}
}
