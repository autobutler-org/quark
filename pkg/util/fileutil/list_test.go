package fileutil

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/indexutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// usbDetector presents a single USB device rooted at a temp dir.
type usbDetector struct {
	mountPoint string
	serial     string
}

func (d *usbDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{
		Name:       "USB Disk",
		MountPoint: d.mountPoint,
		UsbInfo:    &serialOnlyUsbDevice{serial: d.serial},
	}}, nil
}

// serialOnlyUsbDevice implements only GetSerial; any other call panics on the
// nil embedded interface.
type serialOnlyUsbDevice struct {
	storageutil.UsbDevice
	serial string
}

func (u *serialOnlyUsbDevice) GetSerial() string { return u.serial }

// newDeviceRegistry registers svc's devices the way deputil does: the internal
// drive as "files" and one namespace per other device.
func newDeviceRegistry(t testing.TB, svc *storageutil.StorageService) vfs.Registry {
	t.Helper()
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}
	return registry
}

// TestVFSListingsCarryTheDevice is the regression for #1867: every listing
// served through the VFS registry dropped the device name, path and serial.
func TestVFSListingsCarryTheDevice(t *testing.T) {
	const serial = "USB-1867"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "photo.jpg"), []byte("jpg"), 0644); err != nil {
		t.Fatal(err)
	}

	svc := storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: serial})
	registry := newDeviceRegistry(t, svc)
	ctx := context.Background()

	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	listed, err := ListFiles(ListFilesParams{Ctx: ctx, Registry: registry, Access: system.Access})
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	searched, err := SearchFiles(SearchFilesParams{Ctx: ctx, Registry: registry, Query: "photo", Access: system.Access})
	if err != nil {
		t.Fatalf("SearchFiles failed: %v", err)
	}
	recent, err := ListRecent(ListRecentParams{Ctx: ctx, Registry: registry, Access: system.Access})
	if err != nil {
		t.Fatalf("ListRecent failed: %v", err)
	}
	byType, err := ListByType(ListByTypeParams{Ctx: ctx, Registry: registry, FileType: storageutil.FileTypeImage, Access: system.Access})
	if err != nil {
		t.Fatalf("ListByType failed: %v", err)
	}
	// Indexed search (#1896) only knew the serial.
	index := indexutil.NewFileIndex()
	index.Build(context.Background(), registry)
	indexed, err := SearchFiles(SearchFilesParams{Ctx: ctx, Index: index, Registry: registry, Query: "photo", Access: system.Access})
	if err != nil {
		t.Fatalf("indexed SearchFiles failed: %v", err)
	}

	cases := map[string][]FileNode{
		"ListFiles":           listed.Files,
		"SearchFiles":         searched.Files,
		"ListRecent":          recent.Files,
		"ListByType":          byType.Files,
		"indexed SearchFiles": indexed.Files,
	}
	for name, files := range cases {
		if len(files) != 1 {
			t.Errorf("%s: expected 1 file, got %+v", name, files)
			continue
		}
		f := files[0]
		if f.DeviceSerial != serial || f.DeviceName != "USB Disk" || f.DevicePath == "" {
			t.Errorf("%s: device fields not carried through, got serial=%q name=%q path=%q",
				name, f.DeviceSerial, f.DeviceName, f.DevicePath)
		}
		if f.FileType != string(storageutil.FileTypeImage) {
			t.Errorf("%s: expected file type %q, got %q", name, storageutil.FileTypeImage, f.FileType)
		}
	}
}

// namedUSBDetector presents one USB device per name, each rooted at its own
// temp dir.
type namedUSBDetector struct {
	devices []storageutil.Device
}

func (d *namedUSBDetector) DetectDevices() ([]storageutil.Device, error) {
	return d.devices, nil
}

// listOnUSBDevices builds one USB device per name, serial "USB-<name>", and
// returns the registry over them with the files directory of each.
func listOnUSBDevices(t *testing.T, names ...string) (vfs.Registry, []string) {
	t.Helper()
	detector := &namedUSBDetector{}
	var filesDirs []string
	for _, name := range names {
		mountPoint := t.TempDir()
		filesDir := filepath.Join(mountPoint, "quark", "data", "files")
		if err := os.MkdirAll(filesDir, 0755); err != nil {
			t.Fatal(err)
		}
		detector.devices = append(detector.devices, storageutil.Device{
			Name:       name,
			MountPoint: mountPoint,
			UsbInfo:    &serialOnlyUsbDevice{serial: "USB-" + name},
		})
		filesDirs = append(filesDirs, filesDir)
	}
	return newDeviceRegistry(t, storageutil.NewStorageService(detector)), filesDirs
}

// listAsSystem lists rootDir on every device in registry as the system
// principal, who may see everything.
func listAsSystem(t *testing.T, registry vfs.Registry, rootDir string) ([]FileNode, error) {
	t.Helper()
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	result, err := ListFiles(ListFilesParams{Ctx: context.Background(), Registry: registry, Access: system.Access, RootDir: rootDir})
	return result.Files, err
}

func TestListFiles_EmptyDevice(t *testing.T) {
	registry, _ := listOnUSBDevices(t, "test-device")
	result, err := listAsSystem(t, registry, "")
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(result) != 0 {
		t.Errorf("Expected 0 files in empty device, got %d", len(result))
	}
}

func TestListFiles_WithFiles(t *testing.T) {
	registry, filesDirs := listOnUSBDevices(t, "test-device")

	if err := os.WriteFile(filepath.Join(filesDirs[0], "file1.txt"), []byte("hello"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(filesDirs[0], "file2.pdf"), []byte("world"), 0644); err != nil {
		t.Fatal(err)
	}

	result, err := listAsSystem(t, registry, "")
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(result) != 2 {
		t.Errorf("Expected 2 files, got %d", len(result))
	}

	names := make(map[string]bool)
	for _, f := range result {
		names[f.Name] = true
		if f.DeviceName != "test-device" {
			t.Errorf("Expected DeviceName 'test-device', got %q", f.DeviceName)
		}
		if f.IsDir {
			t.Errorf("Expected file, got directory for %q", f.Name)
		}
	}
	if !names["file1.txt"] || !names["file2.pdf"] {
		t.Errorf("Expected file1.txt and file2.pdf, got %v", names)
	}
}

func TestListFiles_WithSubdirectory(t *testing.T) {
	registry, filesDirs := listOnUSBDevices(t, "test-device")

	subdir := filepath.Join(filesDirs[0], "docs")
	if err := os.Mkdir(subdir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(subdir, "readme.txt"), []byte("hi"), 0644); err != nil {
		t.Fatal(err)
	}

	result, err := listAsSystem(t, registry, "")
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(result) != 1 || !result[0].IsDir || result[0].DirPath != "docs" {
		t.Fatalf("Expected the docs dir alone, got %+v", result)
	}

	result, err = listAsSystem(t, registry, "docs")
	if err != nil {
		t.Fatalf("ListFiles for subdir failed: %v", err)
	}
	if len(result) != 1 || result[0].Name != "readme.txt" {
		t.Errorf("Expected readme.txt in docs/, got %+v", result)
	}
}

func TestListFiles_DeduplicateFolders(t *testing.T) {
	// Two devices both have a "photos" folder — should appear once
	registry, filesDirs := listOnUSBDevices(t, "device1", "device2")
	for _, dir := range filesDirs {
		if err := os.Mkdir(filepath.Join(dir, "photos"), 0755); err != nil {
			t.Fatal(err)
		}
	}

	result, err := listAsSystem(t, registry, "")
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(result) != 1 || !result[0].IsDir {
		t.Errorf("Expected 1 deduplicated 'photos' folder, got %+v", result)
	}
}

func TestListFiles_FilesNotDeduplicatedAcrossDevices(t *testing.T) {
	// Files with the same name on two devices should both appear (only folders deduplicate)
	registry, filesDirs := listOnUSBDevices(t, "device1", "device2")
	for _, dir := range filesDirs {
		if err := os.WriteFile(filepath.Join(dir, "backup.zip"), []byte("data"), 0644); err != nil {
			t.Fatal(err)
		}
	}

	result, err := listAsSystem(t, registry, "")
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(result) != 2 {
		t.Errorf("Expected 2 entries (same filename on two devices), got %d", len(result))
	}
}

func TestListFiles_NoDevices(t *testing.T) {
	registry, _ := listOnUSBDevices(t)
	result, err := listAsSystem(t, registry, "")
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(result) != 0 {
		t.Errorf("Expected empty result for no devices, got %d", len(result))
	}
}

func TestListFiles_NonExistentSubdir(t *testing.T) {
	registry, _ := listOnUSBDevices(t, "test-device")

	// Listing a subdir that doesn't exist should fail so the client can render
	// an explicit invalid-folder state instead of an empty listing.
	result, err := listAsSystem(t, registry, "nonexistent")
	var notFound *NotFoundError
	if !errors.As(err, &notFound) {
		t.Fatalf("expected a NotFoundError for a nonexistent subdir, got %v", err)
	}
	if result != nil {
		t.Errorf("expected no results for nonexistent subdir, got %d", len(result))
	}
}

// TestListFiles_NoRegistry: without the internal drive's namespace there is
// nothing to list through, and the listing says so rather than walking disks.
func TestListFiles_NoRegistry(t *testing.T) {
	if _, err := listAsSystem(t, nil, ""); !errors.Is(err, ErrNoFilesNamespace) {
		t.Fatalf("expected ErrNoFilesNamespace, got %v", err)
	}
}

func TestFileNodeJSON_Fields(t *testing.T) {
	registry, filesDirs := listOnUSBDevices(t, "my-device")
	if err := os.WriteFile(filepath.Join(filesDirs[0], "test.txt"), []byte("content"), 0644); err != nil {
		t.Fatal(err)
	}

	result, err := listAsSystem(t, registry, "")
	if err != nil {
		t.Fatalf("ListFiles failed: %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("Expected 1 file, got %d", len(result))
	}

	f := result[0]
	if f.Name != "test.txt" {
		t.Errorf("Expected Name 'test.txt', got %q", f.Name)
	}
	if f.IsDir {
		t.Error("Expected IsDir false")
	}
	if f.DeviceName != "my-device" || f.DeviceSerial != "USB-my-device" {
		t.Errorf("Expected device my-device/USB-my-device, got %q/%q", f.DeviceName, f.DeviceSerial)
	}
	if f.Size != int64(len("content")) {
		t.Errorf("Expected Size %d, got %d", len("content"), f.Size)
	}
	if f.DirPath != "test.txt" || f.FullPath != "test.txt" {
		t.Errorf("Expected DirPath and FullPath test.txt, got %q and %q", f.DirPath, f.FullPath)
	}
}

// TestSearchResultsCarrySizeAndPath is the regression for #2017: the indexed
// search and the VFS fallback left Size and FullPath empty, so every result
// showed as 0 bytes.
func TestSearchResultsCarrySizeAndPath(t *testing.T) {
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filepath.Join(filesDir, "docs"), 0755); err != nil {
		t.Fatal(err)
	}
	const content = "twelve bytes"
	if err := os.WriteFile(filepath.Join(filesDir, "docs", "notes.txt"), []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	svc := storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: "USB-2017"})
	registry := newDeviceRegistry(t, svc)
	ctx := context.Background()
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	listed, err := ListFiles(ListFilesParams{Ctx: ctx, Registry: registry, Access: system.Access, RootDir: "docs"})
	if err != nil || len(listed.Files) != 1 {
		t.Fatalf("ListFiles: %+v, %v", listed.Files, err)
	}
	want := listed.Files[0]

	index := indexutil.NewFileIndex()
	index.Build(context.Background(), registry)
	indexed, err := SearchFiles(SearchFilesParams{Ctx: ctx, Index: index, Registry: registry, Access: system.Access, Query: "notes"})
	if err != nil {
		t.Fatalf("indexed SearchFiles failed: %v", err)
	}
	viaVFS, err := SearchFiles(SearchFilesParams{Ctx: ctx, Registry: registry, Access: system.Access, Query: "notes"})
	if err != nil {
		t.Fatalf("VFS SearchFiles failed: %v", err)
	}

	for name, files := range map[string][]FileNode{"indexed": indexed.Files, "VFS": viaVFS.Files} {
		if len(files) != 1 {
			t.Errorf("%s: expected 1 file, got %+v", name, files)
			continue
		}
		got := files[0]
		if got.Size != int64(len(content)) {
			t.Errorf("%s: size = %d, want %d", name, got.Size, len(content))
		}
		if got.FullPath != want.FullPath {
			t.Errorf("%s: full path = %q, want %q as listed", name, got.FullPath, want.FullPath)
		}
	}
}

// TestListingsCarryModifiedAt is the regression for #1565: only the recent and
// by-type listings reported when a file was last modified, so the file browser
// had nothing to put in a Modified column.
func TestListingsCarryModifiedAt(t *testing.T) {
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatal(err)
	}
	notes := filepath.Join(filesDir, "notes.txt")
	if err := os.WriteFile(notes, []byte("notes"), 0644); err != nil {
		t.Fatal(err)
	}
	mtime := time.Date(2021, time.March, 4, 5, 6, 7, 0, time.UTC)
	if err := os.Chtimes(notes, mtime, mtime); err != nil {
		t.Fatal(err)
	}

	svc := storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: "USB-1565"})
	registry := newDeviceRegistry(t, svc)
	index := indexutil.NewFileIndex()
	index.Build(context.Background(), registry)
	ctx := context.Background()
	system, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	access := system.Access

	cases := map[string]func() ([]FileNode, error){
		"ListFiles through the VFS": func() ([]FileNode, error) {
			r, err := ListFiles(ListFilesParams{Ctx: ctx, Registry: registry, Access: access})
			return r.Files, err
		},
		"SearchFiles from the index": func() ([]FileNode, error) {
			r, err := SearchFiles(SearchFilesParams{Ctx: ctx, Index: index, Registry: registry, Access: access, Query: "notes"})
			return r.Files, err
		},
		"SearchFiles through the VFS": func() ([]FileNode, error) {
			r, err := SearchFiles(SearchFilesParams{Ctx: ctx, Registry: registry, Access: access, Query: "notes"})
			return r.Files, err
		},
	}
	for name, list := range cases {
		files, err := list()
		if err != nil || len(files) != 1 {
			t.Errorf("%s: expected 1 file, got %+v, %v", name, files, err)
			continue
		}
		if !files[0].ModifiedAt.Equal(mtime) {
			t.Errorf("%s: modified at %v, want %v", name, files[0].ModifiedAt, mtime)
		}
	}
}

// TestArchiveListingsCarryModifiedAt covers what an archive can and cannot
// say: an entry's own time is reported, while an entry written without one and
// a folder the archive only implies are left without (#1565).
func TestArchiveListingsCarryModifiedAt(t *testing.T) {
	mtime := time.Date(2021, time.March, 4, 5, 6, 8, 0, time.UTC)
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, header := range []zip.FileHeader{
		{Name: "dated.txt", Modified: mtime},
		{Name: "undated.txt"},
		{Name: "implied/inner.txt", Modified: mtime},
	} {
		if _, err := zw.CreateHeader(&header); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}

	const serial = "USB-1565"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "bundle.zip"), buf.Bytes(), 0644); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	mem := vfs.NewMemVFS(vfs.FilesNamespace(""))
	if err := mem.Write(ctx, "bundle.zip", bytes.NewReader(buf.Bytes()), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, mem); err != nil {
		t.Fatal(err)
	}

	cases := map[string]ListArchiveParams{
		"through the VFS": {Ctx: ctx, Registry: registry, FilePath: "bundle.zip"},
		"on the device": {
			Storage:  storageutil.NewStorageService(&usbDetector{mountPoint: mountPoint, serial: serial}),
			FilePath: "bundle.zip",
			Serial:   serial,
		},
	}
	for name, params := range cases {
		listed, err := ListArchive(params)
		if err != nil {
			t.Errorf("%s: ListArchive failed: %v", name, err)
			continue
		}
		got := map[string]time.Time{}
		for _, e := range listed.Entries {
			got[e.Name] = e.ModifiedAt
		}
		if len(got) != 3 {
			t.Errorf("%s: expected 3 entries, got %+v", name, listed.Entries)
			continue
		}
		if !got["dated.txt"].Equal(mtime) {
			t.Errorf("%s: dated.txt modified at %v, want %v", name, got["dated.txt"], mtime)
		}
		for _, unknown := range []string{"undated.txt", "implied"} {
			if !got[unknown].IsZero() {
				t.Errorf("%s: %s modified at %v, want none", name, unknown, got[unknown])
			}
		}
	}
}
