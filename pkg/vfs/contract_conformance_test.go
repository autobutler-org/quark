package vfs_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// Delete honors Recursive in every implementation. StorageServiceVFS used to
// drop DeleteOptions and RemoveAll whatever it was given (#2640).
func TestVFSConformance_DeleteNonEmptyDirNeedsRecursive(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			err := target.fs.Delete(ctx, "sub", vfs.DeleteOptions{})
			if !errors.Is(err, vfs.ErrNotEmpty) {
				t.Fatalf("Delete non-empty dir without Recursive: got %v, want ErrNotEmpty", err)
			}
			if got := readFile(t, target.fs, "sub/deep.txt"); got != "content of sub/deep.txt" {
				t.Fatalf("a refused delete changed the tree: %q", got)
			}

			if err := target.fs.Delete(ctx, "sub", vfs.DeleteOptions{Recursive: true}); err != nil {
				t.Fatalf("Delete recursive: %v", err)
			}
			for _, p := range []string{"sub", "sub/deep.txt", "sub/nested/deeper.txt"} {
				if _, err := target.fs.Stat(ctx, p); !errors.Is(err, vfs.ErrNotFound) {
					t.Errorf("Stat %s after recursive delete: got %v, want ErrNotFound", p, err)
				}
			}
		})
	}
}

func TestVFSConformance_DeleteEmptyDirAndFile(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			if err := target.fs.MkdirAll(ctx, "empty"); err != nil {
				t.Fatalf("MkdirAll: %v", err)
			}
			if err := target.fs.Delete(ctx, "empty", vfs.DeleteOptions{}); err != nil {
				t.Fatalf("Delete empty dir: %v", err)
			}
			if err := target.fs.Delete(ctx, "top.txt", vfs.DeleteOptions{}); err != nil {
				t.Fatalf("Delete file: %v", err)
			}
			for _, p := range []string{"empty", "top.txt"} {
				if _, err := target.fs.Stat(ctx, p); !errors.Is(err, vfs.ErrNotFound) {
					t.Errorf("Stat %s after delete: got %v, want ErrNotFound", p, err)
				}
			}
		})
	}
}

func TestVFSConformance_DeleteMissingAndRoot(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			if err := target.fs.Delete(ctx, "nope.txt", vfs.DeleteOptions{}); !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("Delete missing: got %v, want ErrNotFound", err)
			}
			for _, root := range []string{"", "/"} {
				if err := target.fs.Delete(ctx, root, vfs.DeleteOptions{Recursive: true}); !errors.Is(err, vfs.ErrPermissionDenied) {
					t.Errorf("Delete root %q: got %v, want ErrPermissionDenied", root, err)
				}
			}
			if got := readFile(t, target.fs, "top.txt"); got != "content of top.txt" {
				t.Errorf("a refused root delete changed the tree: %q", got)
			}
		})
	}
}

func TestVFSConformance_MissingIsNotFoundAndDirIsNotAFile(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			if _, err := target.fs.Stat(ctx, "nope.txt"); !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("Stat missing: got %v, want ErrNotFound", err)
			}
			if _, err := target.fs.Open(ctx, "nope.txt"); !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("Open missing: got %v, want ErrNotFound", err)
			}
			if _, err := target.fs.Open(ctx, "top.txt/inside"); !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("Open under a file: got %v, want ErrNotFound", err)
			}
			if _, err := target.fs.Open(ctx, "sub"); !errors.Is(err, vfs.ErrIsDirectory) {
				t.Errorf("Open dir: got %v, want ErrIsDirectory", err)
			}
		})
	}
}

// A file the service cannot read is not a missing file. StorageServiceVFS
// mapped every Stat and Open failure to ErrNotFound (#2640). Only the
// host-backed namespaces have permissions to deny.
func TestVFSConformance_PermissionErrorIsNotNotFound(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads through any permission")
	}
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			hp, ok := target.fs.(vfs.HostPather)
			if !ok {
				t.Skipf("%s has no host permissions", target.name)
			}
			ctx := context.Background()
			dir, err := hp.HostPath(ctx, "sub")
			if err != nil {
				t.Fatal(err)
			}
			if err := os.Chmod(dir, 0); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })

			if _, err := target.fs.Stat(ctx, "sub/deep.txt"); !errors.Is(err, vfs.ErrPermissionDenied) {
				t.Errorf("Stat unreadable: got %v, want ErrPermissionDenied", err)
			}
			if _, err := target.fs.Open(ctx, "sub/deep.txt"); !errors.Is(err, vfs.ErrPermissionDenied) {
				t.Errorf("Open unreadable: got %v, want ErrPermissionDenied", err)
			}
		})
	}
}

// Of many writers racing for one name with IfNoneMatch "*", exactly one wins.
// A stat before the rename let several through (#2640).
func TestVFSConformance_WriteIfNoneMatchOneRacerWins(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			const racers = 16
			errs := make(chan error, racers)
			var wg sync.WaitGroup
			for i := range racers {
				wg.Add(1)
				go func() {
					defer wg.Done()
					errs <- target.fs.Write(ctx, "race.txt", strings.NewReader(fmt.Sprintf("racer %d", i)), vfs.WriteOptions{IfNoneMatch: "*"})
				}()
			}
			wg.Wait()
			close(errs)

			wins := 0
			for err := range errs {
				switch {
				case err == nil:
					wins++
				case !errors.Is(err, vfs.ErrConflict):
					t.Errorf("a losing racer got %v, want ErrConflict", err)
				}
			}
			if wins != 1 {
				t.Fatalf("%d racers won, want exactly 1", wins)
			}
			if got := readFile(t, target.fs, "race.txt"); !strings.HasPrefix(got, "racer ") {
				t.Errorf("content = %q, want one racer's whole write", got)
			}
		})
	}
}

// A taken name is refused before the reader is touched, so an upload that
// keeps both can retry the next free name with the same stream.
func TestVFSConformance_WriteIfNoneMatchRefusesBeforeReading(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			r := strings.NewReader("never read")
			err := target.fs.Write(context.Background(), "top.txt", r, vfs.WriteOptions{IfNoneMatch: "*"})
			if !errors.Is(err, vfs.ErrConflict) {
				t.Fatalf("Write onto a taken name: got %v, want ErrConflict", err)
			}
			if r.Len() != len("never read") {
				t.Errorf("a refused write read %d bytes of its reader", len("never read")-r.Len())
			}
		})
	}
}
