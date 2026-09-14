package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// --- ParseRecentLimit ---

func TestParseRecentLimit(t *testing.T) {
	cases := []struct {
		raw  string
		want int
	}{
		{"", 20},
		{"5", 5},
		{"200", 200},
		{"201", 200},
		{"0", 20},
		{"-3", 20},
		{"abc", 20},
	}
	for _, tc := range cases {
		if got := fileutil.ParseRecentLimit(tc.raw); got != tc.want {
			t.Errorf("ParseRecentLimit(%q) = %d, want %d", tc.raw, got, tc.want)
		}
	}
}

// --- SelectDevices ---

func TestSelectDevices(t *testing.T) {
	devices := []storageutil.ManagedDevice{{FilesDir: "/tmp/internal/files"}}

	if got := fileutil.SelectDevices(devices, nil); len(got) != 1 {
		t.Errorf("no serials should select every device, got %d", len(got))
	}
	if got := fileutil.SelectDevices(devices, []string{""}); len(got) != 1 {
		t.Errorf("the empty serial should select the internal device, got %d", len(got))
	}
	if got := fileutil.SelectDevices(devices, []string{"NOPE"}); len(got) != 0 {
		t.Errorf("an unknown serial should select nothing, got %d", len(got))
	}
}

// --- JPEGFileName ---

func TestJPEGFileName(t *testing.T) {
	cases := map[string]string{
		"photos/img.heic": "img.jpg",
		"img.png":         "img.jpg",
		"img":             "img.jpg",
	}
	for path, want := range cases {
		if got := fileutil.JPEGFileName(path); got != want {
			t.Errorf("JPEGFileName(%q) = %q, want %q", path, got, want)
		}
	}
}

// --- ListRecent, VFS path ---

func TestListRecentThroughVFS(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	writeMem(t, fsys, "a.txt", "a")
	writeMem(t, fsys, "docs/b.txt", "b")
	writeMem(t, fsys, "docs/c.txt", "c")

	result, err := fileutil.ListRecent(fileutil.ListRecentParams{
		Ctx:      context.Background(),
		Registry: registryWith(t, fsys),
		Limit:    2,
	})
	if err != nil {
		t.Fatalf("ListRecent failed: %v", err)
	}
	if len(result.Files) != 2 {
		t.Fatalf("limit should cap the listing at 2, got %d", len(result.Files))
	}
	for _, f := range result.Files {
		if f.IsDir {
			t.Errorf("a directory reached the recent listing: %q", f.DirPath)
		}
		if f.ModifiedAt.IsZero() {
			t.Errorf("%q came back without a modification time", f.DirPath)
		}
	}
}

// --- ListArchive, VFS path ---

func TestListArchiveThroughVFS(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	writeMem(t, fsys, "bundle.zip", zipWith(t, map[string]string{
		"top.txt":            "top",
		"nested/inner.txt":   "inner",
		"nested/deep/x.txt":  "x",
		"nested/deep/y.txt":  "y",
		"other/unrelated.md": "no",
	}))

	root, err := fileutil.ListArchive(fileutil.ListArchiveParams{
		Ctx:      context.Background(),
		Registry: registryWith(t, fsys),
		FilePath: "bundle.zip",
	})
	if err != nil {
		t.Fatalf("ListArchive failed: %v", err)
	}
	rootNames := map[string]bool{}
	for _, e := range root.Entries {
		rootNames[e.Name] = e.IsDir
	}
	if len(rootNames) != 3 {
		t.Fatalf("the archive root has 3 direct children, got %v", rootNames)
	}
	if rootNames["top.txt"] {
		t.Error("top.txt should be listed as a file")
	}
	if !rootNames["nested"] {
		t.Error("nested/ should be listed as a synthetic directory")
	}

	sub, err := fileutil.ListArchive(fileutil.ListArchiveParams{
		Ctx:      context.Background(),
		Registry: registryWith(t, fsys),
		FilePath: "bundle.zip",
		SubPath:  "nested",
	})
	if err != nil {
		t.Fatalf("ListArchive(subPath) failed: %v", err)
	}
	if len(sub.Entries) != 2 {
		t.Fatalf("nested/ has 2 direct children, got %d", len(sub.Entries))
	}
	for _, e := range sub.Entries {
		// The virtual path is what the client passes back to list deeper.
		if !strings.HasPrefix(e.DirPath, "bundle.zip/nested/") {
			t.Errorf("entry %q has virtual path %q, want it under bundle.zip/nested/", e.Name, e.DirPath)
		}
	}
}

// --- ZipVFSDir ---

func TestZipVFSDirStoresPathsRelativeToTheFolder(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	writeMem(t, fsys, "folder/one.txt", "one")
	writeMem(t, fsys, "folder/sub/two.txt", "two")

	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := fileutil.ZipVFSDir(context.Background(), fsys, "folder", system.Access, &buf); err != nil {
		t.Fatalf("ZipVFSDir failed: %v", err)
	}

	zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		t.Fatalf("the zip is unreadable: %v", err)
	}
	names := map[string]bool{}
	for _, f := range zr.File {
		names[f.Name] = true
	}
	if !names["one.txt"] || !names["sub/two.txt"] {
		t.Errorf("entries should be relative to the folder, got %v", names)
	}
}

// --- helpers ---

func registryWith(t *testing.T, fsys vfs.VFS) vfs.Registry {
	t.Helper()
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, fsys); err != nil {
		t.Fatalf("failed to register the files namespace: %v", err)
	}
	return registry
}

func writeMem(t *testing.T, fsys vfs.VFS, path, content string) {
	t.Helper()
	if err := fsys.Write(context.Background(), path, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
		t.Fatalf("failed to write %q: %v", path, err)
	}
}

func zipWith(t *testing.T, entries map[string]string) string {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, content := range entries {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatalf("failed to create zip entry %q: %v", name, err)
		}
		if _, err := w.Write([]byte(content)); err != nil {
			t.Fatalf("failed to write zip entry %q: %v", name, err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("failed to close the zip: %v", err)
	}
	return buf.String()
}
