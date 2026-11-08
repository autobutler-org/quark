package vfs

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// A link is the same file under a second name, inside the namespace only.
func TestLocalVFS_Link(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "a/old.txt")
	if err := os.Mkdir(filepath.Join(root, "b"), 0o755); err != nil {
		t.Fatal(err)
	}
	fsys, err := NewLocalVFS(root, FilesNamespace(""))
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()

	if err := fsys.Link(ctx, "a/old.txt", "b/new.txt"); err != nil {
		t.Fatalf("Link: %v", err)
	}
	oldInfo, err := os.Stat(filepath.Join(root, "a", "old.txt"))
	if err != nil {
		t.Fatal(err)
	}
	newInfo, err := os.Stat(filepath.Join(root, "b", "new.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if !os.SameFile(oldInfo, newInfo) {
		t.Error("b/new.txt is not a hard link to a/old.txt")
	}

	if err := fsys.Link(ctx, "a/old.txt", "../escape.txt"); !errors.Is(err, ErrPermissionDenied) {
		t.Errorf("Link out of the root = %v, want ErrPermissionDenied", err)
	}
	if err := fsys.Link(ctx, "a/missing.txt", "b/x.txt"); !errors.Is(err, ErrNotFound) {
		t.Errorf("Link of a missing file = %v, want ErrNotFound", err)
	}
	if err := os.Symlink(filepath.Join(root, "a", "old.txt"), filepath.Join(root, "a", "sym")); err != nil {
		t.Fatal(err)
	}
	if err := fsys.Link(ctx, "a/sym", "b/sym"); !errors.Is(err, ErrPermissionDenied) {
		t.Errorf("Link of a symlink = %v, want ErrPermissionDenied", err)
	}
}
