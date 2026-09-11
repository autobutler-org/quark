package storageutil_test

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func seedTree(t *testing.T, root string, rel ...string) {
	t.Helper()
	for _, r := range rel {
		full := filepath.Join(root, filepath.FromSlash(r))
		if strings.HasSuffix(r, "/") {
			if err := os.MkdirAll(full, 0755); err != nil {
				t.Fatalf("mkdir %s: %v", full, err)
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			t.Fatalf("mkdir %s: %v", filepath.Dir(full), err)
		}
		if err := os.WriteFile(full, []byte(r), 0644); err != nil {
			t.Fatalf("write %s: %v", full, err)
		}
	}
}

func collectWalk(t *testing.T, root string) []storageutil.WalkedFile {
	t.Helper()
	var got []storageutil.WalkedFile
	err := storageutil.WalkFilesInDir(context.Background(), root, "dev", "/data", "SERIAL",
		func(f storageutil.WalkedFile) error {
			got = append(got, f)
			return nil
		},
	)
	if err != nil {
		t.Fatalf("WalkFilesInDir: %v", err)
	}
	return got
}

func relPaths(files []storageutil.WalkedFile) []string {
	out := make([]string, 0, len(files))
	for _, f := range files {
		out = append(out, f.RelPath)
	}
	sort.Strings(out)
	return out
}

// The core of #1605: nested files must be reachable. StatFilesInDir, which this
// replaces at every recursive call site, only ever saw the top level.
func TestWalkFilesInDir_ReachesNestedFiles(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "top.txt", "sub/deep.qdoc", "sub/nested/deeper.txt", "empty/")

	got := relPaths(collectWalk(t, root))
	want := []string{"empty", "sub", "sub/deep.qdoc", "sub/nested", "sub/nested/deeper.txt", "top.txt"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("walk\n got: %v\nwant: %v", got, want)
	}
}

func TestWalkFilesInDir_RelPathIsSlashSeparatedAndRootRelative(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "a/b/c.txt")

	for _, f := range collectWalk(t, root) {
		if strings.HasPrefix(f.RelPath, "/") {
			t.Errorf("RelPath should be relative, got %q", f.RelPath)
		}
		if strings.Contains(f.RelPath, "\\") {
			t.Errorf("RelPath should be slash-separated, got %q", f.RelPath)
		}
		if !strings.HasPrefix(f.Info.FullPath, root) {
			t.Errorf("FullPath %q escaped the walk root %q", f.Info.FullPath, root)
		}
	}
}

func TestWalkFilesInDir_DoesNotVisitTheRoot(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "only.txt")

	for _, f := range collectWalk(t, root) {
		if f.RelPath == "." || f.RelPath == "" {
			t.Errorf("walk visited the root itself: %+v", f)
		}
	}
}

func TestWalkFilesInDir_CarriesDeviceMetadata(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "sub/deep.txt")

	for _, f := range collectWalk(t, root) {
		if f.Info.DeviceName != "dev" || f.Info.DevicePath != "/data" || f.Info.DeviceSerial != "SERIAL" {
			t.Errorf("device metadata not propagated: %+v", f.Info)
		}
	}
}

// fs.SkipAll is how a bounded caller stops a walk over a large library instead
// of materializing every file first.
func TestWalkFilesInDir_SkipAllStopsTheWalk(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "a.txt", "b.txt", "c.txt", "sub/d.txt")

	var seen int
	err := storageutil.WalkFilesInDir(context.Background(), root, "dev", "", "",
		func(storageutil.WalkedFile) error {
			seen++
			if seen == 2 {
				return fs.SkipAll
			}
			return nil
		},
	)
	if err != nil {
		t.Fatalf("fs.SkipAll should end the walk cleanly, got %v", err)
	}
	if seen != 2 {
		t.Errorf("expected the walk to stop after 2 entries, saw %d", seen)
	}
}

func TestWalkFilesInDir_SkipDirSkipsSubtree(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "keep.txt", "pruned/hidden.txt", "pruned/deeper/also.txt")

	var seen []string
	err := storageutil.WalkFilesInDir(context.Background(), root, "dev", "", "",
		func(f storageutil.WalkedFile) error {
			if f.RelPath == "pruned" {
				return fs.SkipDir
			}
			seen = append(seen, f.RelPath)
			return nil
		},
	)
	if err != nil {
		t.Fatalf("WalkFilesInDir: %v", err)
	}
	sort.Strings(seen)
	if strings.Join(seen, ",") != "keep.txt" {
		t.Errorf("SkipDir should have pruned the subtree, saw %v", seen)
	}
}

func TestWalkFilesInDir_VisitErrorStopsAndPropagates(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "a.txt", "b.txt")

	sentinel := errors.New("stop here")
	err := storageutil.WalkFilesInDir(context.Background(), root, "dev", "", "",
		func(storageutil.WalkedFile) error { return sentinel },
	)
	if !errors.Is(err, sentinel) {
		t.Errorf("expected the visit error to propagate, got %v", err)
	}
}

func TestWalkFilesInDir_MissingDirReportsPathNotFound(t *testing.T) {
	err := storageutil.WalkFilesInDir(
		context.Background(), filepath.Join(t.TempDir(), "nope"), "dev", "", "",
		func(storageutil.WalkedFile) error { return nil },
	)
	if !errors.Is(err, storageutil.ErrPathNotFound) {
		t.Errorf("expected ErrPathNotFound, got %v", err)
	}
}

// A recursive walk over a large library has to be cancellable.
func TestWalkFilesInDir_HonorsContextCancellation(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "a.txt", "b.txt", "c.txt")

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	err := storageutil.WalkFilesInDir(ctx, root, "dev", "", "",
		func(storageutil.WalkedFile) error {
			t.Error("visit should not be called after cancellation")
			return nil
		},
	)
	if !errors.Is(err, context.Canceled) {
		t.Errorf("expected context.Canceled, got %v", err)
	}
}

// Symlinks are reported but never followed, so the walk cannot escape the root
// or loop — the same containment the single-level listing has.
func TestWalkFilesInDir_DoesNotFollowSymlinks(t *testing.T) {
	outside := t.TempDir()
	seedTree(t, outside, "secret.txt")

	root := t.TempDir()
	seedTree(t, root, "inside.txt")
	if err := os.Symlink(outside, filepath.Join(root, "escape")); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}

	for _, f := range collectWalk(t, root) {
		if strings.Contains(f.RelPath, "secret.txt") {
			t.Errorf("walk followed a symlink out of the root: %q", f.RelPath)
		}
	}
}

// A self-referential symlink must not hang the walk.
func TestWalkFilesInDir_SurvivesSymlinkLoop(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, "sub/file.txt")
	if err := os.Symlink(root, filepath.Join(root, "sub", "loop")); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}

	got := collectWalk(t, root)
	if len(got) == 0 {
		t.Error("expected entries from a tree containing a symlink loop")
	}
}

// #1828: an upload's temp file and the trash must not surface in either
// listing, while a user's own dotfile still does.
func TestListingsSkipInternalEntriesButNotDotfiles(t *testing.T) {
	root := t.TempDir()
	seedTree(t, root, ".vfs-write-123", ".trash/gone.txt", ".env", "docs/.vfs-write-9", "docs/a.txt")

	if got, want := strings.Join(relPaths(collectWalk(t, root)), ","), ".env,docs,docs/a.txt"; got != want {
		t.Errorf("WalkFilesInDir visited %s, want %s", got, want)
	}

	files, err := storageutil.StatFilesInDir(root, "dev", "/data", "SERIAL")
	if err != nil {
		t.Fatalf("StatFilesInDir: %v", err)
	}
	names := make([]string, 0, len(files))
	for _, f := range files {
		names = append(names, f.Name())
	}
	if got, want := strings.Join(names, ","), "docs/,.env"; got != want {
		t.Errorf("StatFilesInDir listed %s, want %s", got, want)
	}
}
