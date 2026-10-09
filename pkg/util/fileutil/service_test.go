package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
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

// --- FilesVFS ---

// FilesVFS picks the namespace by serial, and never answers an unknown serial
// with the internal drive (#2642).
func TestFilesVFSLooksUpTheDevice(t *testing.T) {
	internal := vfs.NewMemVFS(vfs.FilesNamespace(""))
	usb := vfs.NewMemVFS(vfs.FilesNamespace("USB-1"))
	registry := registryWith(t, internal)
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("USB-1")}, usb); err != nil {
		t.Fatal(err)
	}

	if got, err := fileutil.FilesVFS(registry, ""); err != nil || got != internal {
		t.Errorf("the empty serial: got %v, %v; want the internal drive", got, err)
	}
	if got, err := fileutil.FilesVFS(registry, "USB-1"); err != nil || got != usb {
		t.Errorf("USB-1: got %v, %v; want its namespace", got, err)
	}
	var notFound *fileutil.NotFoundError
	if _, err := fileutil.FilesVFS(registry, "NOPE"); !errors.As(err, &notFound) || !errors.Is(err, fileutil.ErrNoDevice) {
		t.Errorf("an unknown serial: got %v, want a NotFoundError wrapping ErrNoDevice", err)
	}
	for name, reg := range map[string]vfs.Registry{"nil": nil, "empty": vfs.NewRegistry()} {
		if _, err := fileutil.FilesVFS(reg, "USB-1"); !errors.Is(err, fileutil.ErrNoFilesNamespace) {
			t.Errorf("%s registry: got %v, want ErrNoFilesNamespace", name, err)
		}
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

	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	result, err := fileutil.ListRecent(fileutil.ListRecentParams{
		Ctx:      context.Background(),
		Registry: registryWith(t, fsys),
		Access:   system.Access,
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

// The entries sit under one folder named after the archive, so extracting it
// makes that folder instead of spilling the contents into the current one.
func TestZipVFSDirWrapsEntriesInTheFolder(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	writeMem(t, fsys, "folder/one.txt", "one")
	writeMem(t, fsys, "folder/sub/two.txt", "two")

	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := fileutil.ZipVFSDir(context.Background(), fsys, "folder", "My Folder", system.Access, &buf); err != nil {
		t.Fatalf("ZipVFSDir failed: %v", err)
	}

	zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		t.Fatalf("the zip is unreadable: %v", err)
	}
	assertZipNames(t, zr, "My Folder/one.txt", "My Folder/sub/two.txt")
}

// The VFS returns paths in one form, with no leading or trailing slash, so a
// base path spelled "/folder/" must still be trimmed off every entry rather
// than nest the whole tree under the archive folder a second time (#2640).
func TestZipVFSDirTrimsABasePathInAnySpelling(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	writeMem(t, fsys, "folder/one.txt", "one")

	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := fileutil.ZipVFSDir(context.Background(), fsys, "/folder/", "My Folder", system.Access, &buf); err != nil {
		t.Fatalf("ZipVFSDir failed: %v", err)
	}
	zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		t.Fatalf("the zip is unreadable: %v", err)
	}
	assertZipNames(t, zr, "My Folder/one.txt")
}

// --- ZipVFSDir on a device ---

// A device folder zips through its namespace the way the internal drive's
// does (#2642): the storage layer's own names stay out, and a symlink no
// longer fails the whole download, as the os.DirFS walk that served devices
// before made it. Whether a link's target goes in is the access check's call,
// which TestDownloadDeviceFolderKeepsToWhatTheCallerReads covers.
func TestZipVFSDirOnADevice(t *testing.T) {
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filepath.Join(filesDir, "folder", "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, content := range map[string]string{"folder/one.txt": "one", "folder/sub/two.txt": "two", "outside.txt": "secret"} {
		if err := os.WriteFile(filepath.Join(filesDir, name), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(filepath.Join(filesDir, "outside.txt"), filepath.Join(filesDir, "folder", "link.txt")); err != nil {
		t.Fatal(err)
	}
	internalName := storageutil.WriteTempPrefix + "partial"
	if err := os.WriteFile(filepath.Join(filesDir, "folder", internalName), []byte("partial"), 0o600); err != nil {
		t.Fatal(err)
	}

	svc := storageutil.NewStorageService(&oneUSBDetector{mountPoint: mountPoint, serial: "USB-ZIP"})
	registry := vfs.NewRegistry()
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}
	fsys, ok := registry.Get(vfs.FilesNamespace("USB-ZIP"))
	if !ok {
		t.Fatal("the device namespace was not registered")
	}
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}

	var buf bytes.Buffer
	if err := fileutil.ZipVFSDir(context.Background(), fsys, "folder", "folder", system.Access, &buf); err != nil {
		t.Fatalf("ZipVFSDir failed: %v", err)
	}
	zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		t.Fatalf("the zip is unreadable: %v", err)
	}
	assertZipNames(t, zr, "folder/one.txt", "folder/sub/two.txt")
	for _, f := range zr.File {
		if strings.Contains(f.Name, storageutil.WriteTempPrefix) {
			t.Errorf("internal name %q reached the archive", f.Name)
		}
	}
}

// oneUSBDetector presents a single USB device rooted at mountPoint.
type oneUSBDetector struct {
	mountPoint string
	serial     string
}

func (d *oneUSBDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{
		Name:       "USB Disk",
		MountPoint: d.mountPoint,
		UsbInfo:    serialUsbDevice{serial: d.serial},
	}}, nil
}

// serialUsbDevice implements only GetSerial; any other call panics on the
// nil embedded interface.
type serialUsbDevice struct {
	storageutil.UsbDevice
	serial string
}

func (u serialUsbDevice) GetSerial() string { return u.serial }

// --- helpers ---

// assertZipNames fails unless every file entry in zr is under a folder and
// the wanted names are among them.
func assertZipNames(t *testing.T, zr *zip.Reader, want ...string) {
	t.Helper()
	names := map[string]bool{}
	for _, f := range zr.File {
		names[f.Name] = true
		if !strings.Contains(strings.TrimSuffix(f.Name, "/"), "/") && !strings.HasSuffix(f.Name, "/") {
			t.Errorf("entry %q is loose at the top of the archive", f.Name)
		}
	}
	for _, name := range want {
		if !names[name] {
			t.Errorf("missing entry %q, got %v", name, names)
		}
	}
}

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
