package vfs_test

import (
	"context"
	"errors"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// readFile opens p in v and returns its content.
func readFile(t *testing.T, v vfs.VFS, p string) string {
	t.Helper()
	f, err := v.Open(context.Background(), p)
	if err != nil {
		t.Fatalf("Open %s: %v", p, err)
	}
	defer f.Close()
	data, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("read %s: %v", p, err)
	}
	return string(data)
}

func TestVFSConformance_CopyWithinNamespace(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			src, dst := target.root+"top.txt", target.root+"copies/top.txt"
			if err := target.fs.Copy(ctx, src, dst, vfs.CopyOptions{}); err != nil {
				t.Fatalf("Copy: %v", err)
			}
			if got := readFile(t, target.fs, dst); got != "content of top.txt" {
				t.Errorf("copy content: got %q", got)
			}
			if got := readFile(t, target.fs, src); got != "content of top.txt" {
				t.Errorf("source changed by copy: got %q", got)
			}
		})
	}
}

// IfNoneMatch "*" refuses a taken destination and leaves it as it was.
func TestVFSConformance_CopyIfNoneMatchRefusesTakenName(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			err := target.fs.Copy(ctx, target.root+"top.txt", target.root+"sub/deep.txt", vfs.CopyOptions{IfNoneMatch: "*"})
			if !errors.Is(err, vfs.ErrConflict) {
				t.Fatalf("Copy onto a taken name: got %v, want ErrConflict", err)
			}
			if got := readFile(t, target.fs, target.root+"sub/deep.txt"); got != "content of sub/deep.txt" {
				t.Errorf("refused copy changed the destination: got %q", got)
			}
		})
	}
}

func TestVFSConformance_CopyDirectoryIsErrIsDirectory(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			err := target.fs.Copy(context.Background(), target.root+"sub", target.root+"sub2", vfs.CopyOptions{})
			if !errors.Is(err, vfs.ErrIsDirectory) {
				t.Fatalf("Copy of a directory: got %v, want ErrIsDirectory", err)
			}
		})
	}
}

func TestVFSConformance_CopyMissingSourceIsNotFound(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			err := target.fs.Copy(context.Background(), target.root+"nope.txt", target.root+"x.txt", vfs.CopyOptions{})
			if !errors.Is(err, vfs.ErrNotFound) {
				t.Fatalf("Copy of a missing file: got %v, want ErrNotFound", err)
			}
		})
	}
}

// failingFile reads a few bytes and then fails, the way a source on a device
// that is unplugged mid-copy does.
type failingFile struct{ vfs.File }

var errSourceGone = errors.New("source went away")

func (f failingFile) Read(p []byte) (int, error) {
	if len(p) > 4 {
		p = p[:4]
	}
	n, _ := f.File.Read(p)
	if n == 0 {
		return 0, errSourceGone
	}
	return n, nil
}

// failingVFS is a MemVFS whose files fail partway through a read.
type failingVFS struct{ *vfs.MemVFS }

func (v failingVFS) Open(ctx context.Context, p string) (vfs.File, error) {
	f, err := v.MemVFS.Open(ctx, p)
	if err != nil {
		return nil, err
	}
	return failingFile{f}, nil
}

// A copy that fails partway leaves nothing under the destination name: not a
// truncated file, and not a temp file in the listing either (#2640).
func TestVFSConformance_CopyBetweenNeverLeavesAPartialFile(t *testing.T) {
	src := failingVFS{vfs.NewMemVFS("src")}
	if err := src.Write(context.Background(), "big.bin", strings.NewReader(strings.Repeat("x", 64)), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			ctx := context.Background()
			before, err := target.fs.List(ctx, target.root, &vfs.ListFilter{Recursive: true})
			if err != nil {
				t.Fatal(err)
			}
			err = vfs.CopyBetween(ctx, src, "big.bin", target.fs, target.root+"big.bin", vfs.CopyOptions{})
			if !errors.Is(err, errSourceGone) {
				t.Fatalf("CopyBetween: got %v, want the source's read error", err)
			}
			if _, err := target.fs.Stat(ctx, target.root+"big.bin"); !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("a failed copy left something at the destination: Stat = %v", err)
			}
			after, err := target.fs.List(ctx, target.root, &vfs.ListFilter{Recursive: true})
			if err != nil {
				t.Fatal(err)
			}
			if len(after) != len(before) {
				t.Errorf("a failed copy changed the listing: %d entries before, %d after: %v", len(before), len(after), after)
			}
		})
	}
}

func TestVFSConformance_CopyBetweenNamespaces(t *testing.T) {
	src := vfs.NewMemVFS("src")
	if err := src.Write(context.Background(), "a/photo.jpg", strings.NewReader("jpeg bytes"), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			dst := target.root + "from-mem/photo.jpg"
			if err := vfs.CopyBetween(context.Background(), src, "a/photo.jpg", target.fs, dst, vfs.CopyOptions{}); err != nil {
				t.Fatalf("CopyBetween: %v", err)
			}
			if got := readFile(t, target.fs, dst); got != "jpeg bytes" {
				t.Errorf("copied content: got %q", got)
			}
			err := vfs.CopyBetween(context.Background(), src, "a/photo.jpg", target.fs, dst, vfs.CopyOptions{IfNoneMatch: "*"})
			if !errors.Is(err, vfs.ErrConflict) {
				t.Errorf("CopyBetween onto a taken name: got %v, want ErrConflict", err)
			}
		})
	}
}

// The namespaces backed by a host directory resolve a path to it; the ones
// that hold content in memory or a database have no host path to give.
func TestVFSConformance_HostPath(t *testing.T) {
	hosted := map[string]bool{"LocalVFS": true, "StorageServiceVFS": true, "StorageServiceVFS/device": true}
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			hp, ok := target.fs.(vfs.HostPather)
			if ok != hosted[target.name] {
				t.Fatalf("implements HostPather = %v, want %v", ok, hosted[target.name])
			}
			if !ok {
				return
			}
			ctx := context.Background()
			p, err := hp.HostPath(ctx, "sub/deep.txt")
			if err != nil {
				t.Fatalf("HostPath: %v", err)
			}
			data, err := os.ReadFile(p)
			if err != nil {
				t.Fatalf("host path %s does not name the file: %v", p, err)
			}
			if string(data) != "content of sub/deep.txt" {
				t.Errorf("host path content: got %q", data)
			}
			if _, err := hp.HostPath(ctx, "../outside.txt"); !errors.Is(err, vfs.ErrPermissionDenied) {
				t.Errorf("HostPath escaping the namespace: got %v, want ErrPermissionDenied", err)
			}
		})
	}
}
