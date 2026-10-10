package vfs_test

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// deviceMount is a fake device's mount point and the files directory under it.
type deviceMount struct {
	mountPoint string
	filesDir   string
}

func newDeviceMount(t *testing.T) deviceMount {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatal(err)
	}
	return deviceMount{mountPoint: mountPoint, filesDir: filesDir}
}

// device describes the mount as a detected device: the internal drive for the
// empty serial, a USB drive otherwise.
func (m deviceMount) device(serial string) storageutil.Device {
	if serial == "" {
		return storageutil.Device{Name: "Internal", MountPoint: m.mountPoint, IsInternal: true}
	}
	return storageutil.Device{Name: "USB " + serial, MountPoint: m.mountPoint, UsbInfo: serialUsbDevice{serial: serial}}
}

// serialUsbDevice implements only GetSerial; any other call panics on the nil
// embedded interface.
type serialUsbDevice struct {
	storageutil.UsbDevice
	serial string
}

func (u serialUsbDevice) GetSerial() string { return u.serial }

// devicesDetector reports a device set a test can change, the way plugging
// and unplugging a drive changes what the real detector finds.
type devicesDetector struct {
	mu      sync.Mutex
	devices []storageutil.Device
}

func newDevicesDetector(devices ...storageutil.Device) *devicesDetector {
	return &devicesDetector{devices: devices}
}

func (d *devicesDetector) DetectDevices() ([]storageutil.Device, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return slices.Clone(d.devices), nil
}

func (d *devicesDetector) set(devices ...storageutil.Device) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.devices = devices
}

func writeOnDisk(t *testing.T, root, rel, content string) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func namespaceIDs(registry vfs.Registry) []string {
	var ids []string
	for _, ns := range registry.List("") {
		ids = append(ids, ns.ID)
	}
	sort.Strings(ids)
	return ids
}

// newDeviceRegistry registers the internal drive as "files" and wires the
// sync to the storage service, the way deputil.DefaultDependencies does.
func newDeviceRegistry(t *testing.T, svc *storageutil.StorageService) vfs.Registry {
	t.Helper()
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}
	sync := func() {
		if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
			t.Errorf("SyncDeviceNamespaces: %v", err)
		}
	}
	svc.OnDevicesChanged(sync)
	sync()
	return registry
}

func TestFilesNamespace(t *testing.T) {
	if got := vfs.FilesNamespace(""); got != "files" {
		t.Errorf("internal drive namespace = %q, want files", got)
	}
	if got := vfs.FilesNamespace("ABC123"); got != "files:ABC123" {
		t.Errorf("device namespace = %q, want files:ABC123", got)
	}
}

// TestDeviceNamespacesFollowMounts checks the registry holds one namespace per
// managed device and that the set follows a mount and an unmount (#2639).
func TestDeviceNamespacesFollowMounts(t *testing.T) {
	internal, usbA, usbB := newDeviceMount(t), newDeviceMount(t), newDeviceMount(t)
	detector := newDevicesDetector(internal.device(""), usbA.device("A"))
	svc := storageutil.NewStorageService(detector)
	registry := newDeviceRegistry(t, svc)

	if got, want := namespaceIDs(registry), []string{"files", "files:A"}; !slices.Equal(got, want) {
		t.Fatalf("at startup namespaces = %v, want %v", got, want)
	}

	detector.set(internal.device(""), usbA.device("A"), usbB.device("B"))
	svc.InvalidateDeviceCache()
	if got, want := namespaceIDs(registry), []string{"files", "files:A", "files:B"}; !slices.Equal(got, want) {
		t.Fatalf("after mounting B namespaces = %v, want %v", got, want)
	}

	detector.set(internal.device(""), usbB.device("B"))
	svc.InvalidateDeviceCache()
	if got, want := namespaceIDs(registry), []string{"files", "files:B"}; !slices.Equal(got, want) {
		t.Fatalf("after unmounting A namespaces = %v, want %v", got, want)
	}
	if _, ok := registry.Get(vfs.FilesNamespace("A")); ok {
		t.Error("the unmounted device's namespace is still registered")
	}
}

func TestSyncDeviceNamespacesReportsChanges(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	detector := newDevicesDetector(internal.device(""), usb.device("A"))
	svc := storageutil.NewStorageService(detector)
	registry := vfs.NewRegistry()

	first, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(first.Registered, []string{"files:A"}) || len(first.Unregistered) != 0 {
		t.Errorf("first sync = %+v, want files:A registered", first)
	}
	again, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc})
	if err != nil {
		t.Fatal(err)
	}
	if len(again.Registered) != 0 || len(again.Unregistered) != 0 {
		t.Errorf("an unchanged device set changed the registry: %+v", again)
	}

	detector.set(internal.device(""))
	svc.InvalidateDeviceCache()
	gone, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(gone.Unregistered, []string{"files:A"}) {
		t.Errorf("after unplugging = %+v, want files:A unregistered", gone)
	}
	if _, ok := registry.Get(vfs.FilesNamespace("")); ok {
		t.Error("the sync registered the internal drive; that is deputil's job")
	}
}

// TestDeviceNamespaceAddressesItsDevice checks every single-path operation of
// a device namespace lands on that device's files directory, not the
// internal drive's. Before #2639 each one called the StorageService without a
// serial and reached the internal drive.
func TestDeviceNamespaceAddressesItsDevice(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	writeOnDisk(t, internal.filesDir, "same.txt", "internal")
	writeOnDisk(t, usb.filesDir, "same.txt", "usb")
	writeOnDisk(t, internal.filesDir, "internal-only.txt", "internal")
	svc := storageutil.NewStorageService(newDevicesDetector(internal.device(""), usb.device("A")))
	registry := newDeviceRegistry(t, svc)
	ctx := context.Background()

	fsys, ok := registry.Get(vfs.FilesNamespace("A"))
	if !ok {
		t.Fatal("no namespace for the attached device")
	}

	r, err := fsys.Open(ctx, "same.txt")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	body, _ := io.ReadAll(r)
	_ = r.Close()
	if string(body) != "usb" {
		t.Errorf("Open read %q, want the USB copy", body)
	}
	if _, err := fsys.Stat(ctx, "internal-only.txt"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("Stat of an internal-only file = %v, want ErrNotFound", err)
	}

	if err := fsys.MkdirAll(ctx, "made"); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := fsys.Write(ctx, "made/new.txt", strings.NewReader("new"), vfs.WriteOptions{}); err != nil {
		t.Fatalf("Write: %v", err)
	}
	if err := fsys.Move(ctx, "made/new.txt", "made/moved.txt"); err != nil {
		t.Fatalf("Move: %v", err)
	}
	if _, err := os.Stat(filepath.Join(usb.filesDir, "made", "moved.txt")); err != nil {
		t.Errorf("the write and move did not land on the USB drive: %v", err)
	}
	if _, err := os.Stat(filepath.Join(internal.filesDir, "made")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the device namespace touched the internal drive: %v", err)
	}

	if err := fsys.Delete(ctx, "same.txt", vfs.DeleteOptions{}); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := os.Stat(filepath.Join(internal.filesDir, "same.txt")); err != nil {
		t.Errorf("deleting on the USB drive removed the internal copy: %v", err)
	}
}

// TestUnknownSerialIsNotFound checks a serial with no attached device never
// reaches the internal drive: it has no namespace, and a namespace left over
// from a drive that has since gone answers ErrNotFound to everything.
func TestUnknownSerialIsNotFound(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	writeOnDisk(t, internal.filesDir, "doc.txt", "internal")
	detector := newDevicesDetector(internal.device(""), usb.device("A"))
	svc := storageutil.NewStorageService(detector)
	registry := newDeviceRegistry(t, svc)
	ctx := context.Background()

	if _, ok := registry.Get(vfs.FilesNamespace("NOT-ATTACHED")); ok {
		t.Error("an unattached serial resolved to a namespace")
	}

	// Hold on to the namespace across the unplug, as a request in flight would.
	stale, ok := registry.Get(vfs.FilesNamespace("A"))
	if !ok {
		t.Fatal("no namespace for the attached device")
	}
	detector.set(internal.device(""))
	svc.InvalidateDeviceCache()

	if _, err := stale.Stat(ctx, "doc.txt"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("Stat = %v, want ErrNotFound", err)
	}
	if _, err := stale.Open(ctx, "doc.txt"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("Open = %v, want ErrNotFound", err)
	}
	if err := stale.Write(ctx, "new.txt", strings.NewReader("x"), vfs.WriteOptions{}); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("Write = %v, want ErrNotFound", err)
	}
	if err := stale.MkdirAll(ctx, "dir"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("MkdirAll = %v, want ErrNotFound", err)
	}
	if err := stale.Move(ctx, "doc.txt", "moved.txt"); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("Move = %v, want ErrNotFound", err)
	}
	if err := stale.Delete(ctx, "doc.txt", vfs.DeleteOptions{}); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("Delete = %v, want ErrNotFound", err)
	}
	entries, err := stale.List(ctx, "", nil)
	if err != nil || len(entries) != 0 {
		t.Errorf("List = %v, %v; want nothing", entries, err)
	}

	for _, name := range []string{"doc.txt", "new.txt", "dir", "moved.txt"} {
		_, err := os.Stat(filepath.Join(internal.filesDir, name))
		if (name == "doc.txt") != (err == nil) {
			t.Errorf("internal drive %s: %v — the stale namespace reached it", name, err)
		}
	}
}

func listedPaths(entries []vfs.FileInfo) []string {
	var out []string
	for _, e := range entries {
		suffix := ""
		if e.IsDir {
			suffix = "/"
		}
		out = append(out, e.Path+suffix+"@"+e.DeviceSerial)
	}
	sort.Strings(out)
	return out
}

// TestListDevices checks the fan-out returns what the merged List used to: a
// folder on several devices once, as the internal drive reports it, every file
// with the device it is on, and SerialFilter selecting devices.
func TestListDevices(t *testing.T) {
	internal, usb := newDeviceMount(t), newDeviceMount(t)
	writeOnDisk(t, internal.filesDir, "shared/a.txt", "a")
	writeOnDisk(t, usb.filesDir, "shared/b.txt", "b")
	writeOnDisk(t, usb.filesDir, "usb.txt", "u")
	svc := storageutil.NewStorageService(newDevicesDetector(internal.device(""), usb.device("A")))
	registry := newDeviceRegistry(t, svc)
	ctx := context.Background()

	cases := []struct {
		name   string
		path   string
		filter *vfs.ListFilter
		want   []string
	}{
		{"root", "", nil, []string{"shared/@", "usb.txt@A"}},
		{"recursive", "", &vfs.ListFilter{Recursive: true}, []string{"shared/@", "shared/a.txt@", "shared/b.txt@A", "usb.txt@A"}},
		{"subfolder", "shared", nil, []string{"shared/a.txt@", "shared/b.txt@A"}},
		{"internal only", "", &vfs.ListFilter{Recursive: true, SerialFilter: []string{""}}, []string{"shared/@", "shared/a.txt@"}},
		{"usb only", "", &vfs.ListFilter{Recursive: true, SerialFilter: []string{"A"}}, []string{"shared/@A", "shared/b.txt@A", "usb.txt@A"}},
		{"unattached serial", "", &vfs.ListFilter{SerialFilter: []string{"NOT-ATTACHED"}}, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			entries, err := vfs.ListDevices(vfs.ListDevicesParams{Ctx: ctx, Registry: registry, Path: tc.path, Filter: tc.filter})
			if err != nil {
				t.Fatal(err)
			}
			if got := listedPaths(entries); !slices.Equal(got, tc.want) {
				t.Errorf("listed %v, want %v", got, tc.want)
			}
		})
	}

	if _, err := vfs.ListDevices(vfs.ListDevicesParams{Ctx: ctx, Registry: registry, Path: "missing"}); !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("a folder on no device = %v, want ErrNotFound", err)
	}
	limited, err := vfs.ListDevices(vfs.ListDevicesParams{Ctx: ctx, Registry: registry, Filter: &vfs.ListFilter{Recursive: true, MaxResults: 2}})
	if err != nil {
		t.Fatal(err)
	}
	if len(limited) != 2 {
		t.Errorf("MaxResults 2 listed %d entries", len(limited))
	}
}
