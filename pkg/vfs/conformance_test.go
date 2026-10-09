package vfs_test

import (
	"context"
	"io"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// A ListFilter field that one implementation honors and another silently drops
// is a trap: the caller has no way to tell the difference between "no matches"
// and "the filter was ignored". StorageServiceVFS dropped Recursive for exactly
// that reason, which emptied the Docs page, Recent files, and filename search
// (#1605).
//
// This suite runs the same fixture tree through every VFS implementation.
//
// Support matrix — a sub-test skips where an implementation declares no
// support, so the gaps are visible in test output rather than silently
// untested:
//
//	                    Recursive  MaxResults  MimePrefix  AfterPath
//	MemVFS                  yes        yes         yes        yes
//	LocalVFS                yes        yes         yes        yes
//	DBVFS                   yes        yes          no         no
//	StorageServiceVFS       yes        yes         yes        yes
//	  (device-scoped)       yes        yes         yes        yes
type conformanceTarget struct {
	name string
	fs   vfs.VFS
	// root is the path to pass to List for the top of the fixture tree.
	root string
	// canonical maps a returned FileInfo.Path to a slash-separated path
	// relative to root, so implementations with different path conventions
	// (DBVFS uses leading slashes and trailing slashes on directories) can be
	// compared against one shared set of expectations.
	canonical func(string) string

	supportsMimePrefix bool
	supportsAfterPath  bool
}

// fixtureFiles is the tree every target is seeded with. Two files sit at the
// root and two are nested, which is the distinction a dropped Recursive erases.
var fixtureFiles = []string{
	"top.txt",
	"top.png",
	"sub/deep.txt",
	"sub/nested/deeper.txt",
}

func conformanceTargets(t *testing.T) []conformanceTarget {
	t.Helper()
	return []conformanceTarget{
		newMemTarget(t),
		newLocalTarget(t),
		newDBTarget(t),
		newStorageServiceTarget(t),
		newDeviceStorageServiceTarget(t),
	}
}

func seedWrites(t *testing.T, v vfs.VFS, prefix string) {
	t.Helper()
	ctx := context.Background()
	for _, f := range fixtureFiles {
		p := prefix + f
		if dir := path.Dir(f); dir != "." {
			if err := v.MkdirAll(ctx, prefix+dir); err != nil {
				t.Fatalf("MkdirAll %s: %v", prefix+dir, err)
			}
		}
		if err := v.Write(ctx, p, strings.NewReader("content of "+f), vfs.WriteOptions{}); err != nil {
			t.Fatalf("Write %s: %v", p, err)
		}
	}
}

func newMemTarget(t *testing.T) conformanceTarget {
	v := vfs.NewMemVFS("mem")
	seedWrites(t, v, "")
	return conformanceTarget{
		name:               "MemVFS",
		fs:                 v,
		root:               "",
		canonical:          trimSlashes,
		supportsMimePrefix: true,
		supportsAfterPath:  true,
	}
}

func newLocalTarget(t *testing.T) conformanceTarget {
	root := t.TempDir()
	seedOnDisk(t, root)
	v, err := vfs.NewLocalVFS(root, "local")
	if err != nil {
		t.Fatalf("NewLocalVFS: %v", err)
	}
	return conformanceTarget{
		name:               "LocalVFS",
		fs:                 v,
		root:               "",
		canonical:          trimSlashes,
		supportsMimePrefix: true,
		supportsAfterPath:  true,
	}
}

func newDBTarget(t *testing.T) conformanceTarget {
	v := vfs.NewDBVFS(newTestDB(t), "db")
	seedWrites(t, v, "/")
	return conformanceTarget{
		name:      "DBVFS",
		fs:        v,
		root:      "/",
		canonical: trimSlashes,
		// DBVFS reads only Recursive and MaxResults off ListFilter today.
		supportsMimePrefix: false,
		supportsAfterPath:  false,
	}
}

// conformanceDetector presents a single internal device rooted at a temp dir,
// the same shape the files API integration tests use.
type conformanceDetector struct{ mountPoint string }

func (d *conformanceDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{
		Name:       "Conformance Device",
		MountPoint: d.mountPoint,
		IsInternal: true,
	}}, nil
}

func newStorageServiceTarget(t *testing.T) conformanceTarget {
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("mkdir files dir: %v", err)
	}
	seedOnDisk(t, filesDir)

	svc := storageutil.NewStorageService(&conformanceDetector{mountPoint: mountPoint})
	return conformanceTarget{
		name:               "StorageServiceVFS",
		fs:                 vfs.NewStorageServiceVFS(svc, "files"),
		root:               "",
		canonical:          trimSlashes,
		supportsMimePrefix: true,
		supportsAfterPath:  true,
	}
}

// newDeviceStorageServiceTarget is a StorageServiceVFS scoped to a USB device,
// the namespace each non-internal device gets (#2639). The internal drive
// beside it holds a file of its own, which no listing here may show.
func newDeviceStorageServiceTarget(t *testing.T) conformanceTarget {
	const serial = "USB-CONFORMANCE"
	internal := newDeviceMount(t)
	usb := newDeviceMount(t)
	seedOnDisk(t, usb.filesDir)
	if err := os.WriteFile(filepath.Join(internal.filesDir, "internal-only.txt"), []byte("internal"), 0644); err != nil {
		t.Fatal(err)
	}

	svc := storageutil.NewStorageService(newDevicesDetector(internal.device(""), usb.device(serial)))
	return conformanceTarget{
		name:               "StorageServiceVFS/device",
		fs:                 vfs.NewDeviceStorageServiceVFS(svc, serial),
		root:               "",
		canonical:          trimSlashes,
		supportsMimePrefix: true,
		supportsAfterPath:  true,
	}
}

func seedOnDisk(t *testing.T, root string) {
	t.Helper()
	for _, f := range fixtureFiles {
		full := filepath.Join(root, filepath.FromSlash(f))
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			t.Fatalf("mkdir %s: %v", filepath.Dir(full), err)
		}
		if err := os.WriteFile(full, []byte("content of "+f), 0644); err != nil {
			t.Fatalf("write %s: %v", full, err)
		}
	}
}

func trimSlashes(p string) string {
	return strings.Trim(filepath.ToSlash(p), "/")
}

// filePaths returns the canonical paths of the non-directory entries.
func filePaths(target conformanceTarget, entries []vfs.FileInfo) []string {
	var out []string
	for _, e := range entries {
		if e.IsDir {
			continue
		}
		out = append(out, target.canonical(e.Path))
	}
	sort.Strings(out)
	return out
}

func TestVFSConformance_Recursive(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			entries, err := target.fs.List(context.Background(), target.root, &vfs.ListFilter{Recursive: true})
			if err != nil {
				t.Fatalf("List recursive: %v", err)
			}
			got := filePaths(target, entries)
			want := []string{"sub/deep.txt", "sub/nested/deeper.txt", "top.png", "top.txt"}
			if strings.Join(got, ",") != strings.Join(want, ",") {
				t.Errorf("recursive list\n got: %v\nwant: %v", got, want)
			}
		})
	}
}

// The other half of the contract: Recursive:false must NOT descend, or callers
// that page through a tree level by level would see duplicates.
func TestVFSConformance_NonRecursiveStaysAtOneLevel(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			entries, err := target.fs.List(context.Background(), target.root, &vfs.ListFilter{Recursive: false})
			if err != nil {
				t.Fatalf("List non-recursive: %v", err)
			}
			got := filePaths(target, entries)
			want := []string{"top.png", "top.txt"}
			if strings.Join(got, ",") != strings.Join(want, ",") {
				t.Errorf("non-recursive list\n got: %v\nwant: %v", got, want)
			}
		})
	}
}

// A recursive walk over a large library must be bounded by MaxResults rather
// than materializing everything and truncating afterwards.
func TestVFSConformance_MaxResultsBoundsRecursiveWalk(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			const maxResults = 2
			entries, err := target.fs.List(context.Background(), target.root, &vfs.ListFilter{
				Recursive:  true,
				MaxResults: maxResults,
			})
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			if len(entries) > maxResults {
				t.Errorf("MaxResults=%d returned %d entries: %v", maxResults, len(entries), entries)
			}
			if len(entries) == 0 {
				t.Error("MaxResults should cap the result, not empty it")
			}
		})
	}
}

func TestVFSConformance_MimePrefixFiltersRecursively(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			if !target.supportsMimePrefix {
				t.Skipf("%s does not read ListFilter.MimePrefix", target.name)
			}
			entries, err := target.fs.List(context.Background(), target.root, &vfs.ListFilter{
				Recursive:  true,
				MimePrefix: "image/",
			})
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			got := filePaths(target, entries)
			want := []string{"top.png"}
			if strings.Join(got, ",") != strings.Join(want, ",") {
				t.Errorf("MimePrefix=image/\n got: %v\nwant: %v", got, want)
			}
		})
	}
}

func TestVFSConformance_AfterPathSkipsEarlierEntries(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			if !target.supportsAfterPath {
				t.Skipf("%s does not read ListFilter.AfterPath", target.name)
			}
			all, err := target.fs.List(context.Background(), target.root, &vfs.ListFilter{Recursive: true})
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			if len(all) < 2 {
				t.Fatalf("fixture should produce at least 2 entries, got %d", len(all))
			}
			sort.Slice(all, func(i, j int) bool { return all[i].Path < all[j].Path })
			cursor := all[0].Path

			after, err := target.fs.List(context.Background(), target.root, &vfs.ListFilter{
				Recursive: true,
				AfterPath: cursor,
			})
			if err != nil {
				t.Fatalf("List with AfterPath: %v", err)
			}
			for _, e := range after {
				if e.Path <= cursor {
					t.Errorf("AfterPath=%q returned %q, which is not after the cursor", cursor, e.Path)
				}
			}
		})
	}
}

// Open hands back a vfs.File in every implementation: it seeks and reads at an
// offset, so no caller has to type-assert the reader or buffer a stream to get
// random access (#2640).
func TestVFSConformance_OpenSeeksAndReadsAt(t *testing.T) {
	for _, target := range conformanceTargets(t) {
		t.Run(target.name, func(t *testing.T) {
			f, err := target.fs.Open(context.Background(), target.root+"sub/deep.txt")
			if err != nil {
				t.Fatalf("Open: %v", err)
			}
			defer f.Close()

			const content = "content of sub/deep.txt"
			size, err := f.Seek(0, io.SeekEnd)
			if err != nil {
				t.Fatalf("Seek end: %v", err)
			}
			if size != int64(len(content)) {
				t.Errorf("size from Seek: got %d, want %d", size, len(content))
			}

			at := make([]byte, 3)
			if _, err := f.ReadAt(at, 11); err != nil {
				t.Fatalf("ReadAt: %v", err)
			}
			if string(at) != "sub" {
				t.Errorf("ReadAt(11): got %q, want %q", at, "sub")
			}

			if _, err := f.Seek(0, io.SeekStart); err != nil {
				t.Fatalf("Seek start: %v", err)
			}
			all, err := io.ReadAll(f)
			if err != nil {
				t.Fatalf("ReadAll: %v", err)
			}
			if string(all) != content {
				t.Errorf("read after seek: got %q, want %q", all, content)
			}
		})
	}
}
