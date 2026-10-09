package vfs_test

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// walkPaths walks root and returns every visited path relative to it, in visit order.
func walkPaths(t *testing.T, target conformanceTarget, skip string) []string {
	t.Helper()
	var got []string
	err := vfs.Walk(context.Background(), target.fs, target.root, func(fi vfs.FileInfo) error {
		p := target.canonical(fi.Path)
		got = append(got, p)
		if fi.IsDir && p == skip {
			return fs.SkipDir
		}
		return nil
	})
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	return got
}

// TestWalk holds every namespace to one walk: each entry once, a directory
// before what it holds, names in order within a directory.
func TestWalk(t *testing.T) {
	want := []string{"sub", "sub/deep.txt", "sub/nested", "sub/nested/deeper.txt", "top.png", "top.txt"}
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			if got := walkPaths(t, target, ""); !slices.Equal(got, want) {
				t.Errorf("Walk visited %v, want %v", got, want)
			}
		})
	}
}

// TestWalkSkipDir checks fs.SkipDir leaves a directory's contents out and the walk goes on.
func TestWalkSkipDir(t *testing.T) {
	want := []string{"sub", "sub/deep.txt", "sub/nested", "top.png", "top.txt"}
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			if got := walkPaths(t, target, "sub/nested"); !slices.Equal(got, want) {
				t.Errorf("Walk visited %v, want %v", got, want)
			}
		})
	}
}

// TestWalkSkipAll checks fs.SkipAll ends the walk as a success.
func TestWalkSkipAll(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			visits := 0
			err := vfs.Walk(context.Background(), target.fs, target.root, func(vfs.FileInfo) error {
				visits++
				return fs.SkipAll
			})
			if err != nil || visits != 1 {
				t.Errorf("Walk = %v after %d visits, want nil after 1", err, visits)
			}
		})
	}
}

// TestWalkMissingAndTrash checks a missing path is ErrNotFound and the trash is never walked.
func TestWalkMissingAndTrash(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			noop := func(vfs.FileInfo) error { return nil }
			if err := vfs.Walk(context.Background(), target.fs, "missing", noop); !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("Walk(missing) = %v, want ErrNotFound", err)
			}
			if err := vfs.Walk(context.Background(), target.fs, ".trash/x", noop); !errors.Is(err, vfs.ErrPermissionDenied) {
				t.Errorf("Walk(.trash/x) = %v, want ErrPermissionDenied", err)
			}
		})
	}
}

// TestWalkSkipsInternalNames checks the versions folder and an old in-tree
// trash never surface, and an unreadable folder is skipped, not fatal.
func TestWalkSkipsInternalNames(t *testing.T) {
	internal := newDeviceMount(t)
	writeOnDisk(t, internal.filesDir, "keep.txt", "k")
	writeOnDisk(t, internal.filesDir, ".trash/old.txt", "t")
	writeOnDisk(t, internal.filesDir, storageutil.VersionsDirName+"/v.txt", "v")
	writeOnDisk(t, internal.filesDir, "locked/hidden.txt", "h")
	locked := filepath.Join(internal.filesDir, "locked")
	if err := os.Chmod(locked, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })

	svc := storageutil.NewStorageService(newDevicesDetector(internal.device("")))
	var got []string
	err := vfs.Walk(context.Background(), vfs.NewStorageServiceVFS(svc, "files"), "", func(fi vfs.FileInfo) error {
		got = append(got, fi.Path)
		return nil
	})
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	if os.Geteuid() != 0 && !slices.Equal(got, []string{"keep.txt", "locked"}) {
		t.Errorf("Walk visited %v, want [keep.txt locked]", got)
	}
}

// TestFilesNamespaces checks it returns every device's files namespace by
// serial, and nothing else the registry holds.
func TestFilesNamespaces(t *testing.T) {
	registry := vfs.NewRegistry()
	for _, id := range []string{vfs.FilesNamespace(""), vfs.FilesNamespace("A"), "photos"} {
		if err := registry.Register(vfs.Namespace{ID: id}, vfs.NewMemVFS(id)); err != nil {
			t.Fatal(err)
		}
	}
	got := vfs.FilesNamespaces(registry)
	if len(got) != 2 || got[""] == nil || got["A"] == nil {
		t.Errorf("FilesNamespaces = %v, want the internal drive and A", got)
	}
	if len(vfs.FilesNamespaces(nil)) != 0 {
		t.Error("FilesNamespaces(nil) is not empty")
	}
}
