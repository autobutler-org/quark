package indexutil

import (
	"os"
	"path/filepath"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// mount is a fake device: its mount point and the files directory under it.
type mount struct {
	mountPoint string
	filesDir   string
	serial     string
}

func newMount(t testing.TB, serial string) mount {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	return mount{mountPoint: mountPoint, filesDir: filesDir, serial: serial}
}

// device describes the mount as a detected device: the internal drive for the
// empty serial, a USB drive otherwise.
func (m mount) device() storageutil.Device {
	if m.serial == "" {
		return storageutil.Device{Name: "Internal", MountPoint: m.mountPoint, IsInternal: true}
	}
	return storageutil.Device{Name: "USB " + m.serial, MountPoint: m.mountPoint, UsbInfo: serialUsbDevice{serial: m.serial}}
}

// serialUsbDevice implements only GetSerial; any other call panics on the nil
// embedded interface.
type serialUsbDevice struct {
	storageutil.UsbDevice
	serial string
}

func (u serialUsbDevice) GetSerial() string { return u.serial }

// detector reports a device set a test can change, the way plugging and
// unplugging a drive changes what the real detector finds.
type detector struct {
	mu      sync.Mutex
	devices []storageutil.Device
}

func (d *detector) DetectDevices() ([]storageutil.Device, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return slices.Clone(d.devices), nil
}

func (d *detector) set(mounts ...mount) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.devices = nil
	for _, m := range mounts {
		d.devices = append(d.devices, m.device())
	}
}

// devices is a storage service over mounts and a registry holding one files
// namespace per device, kept in step the way deputil.DefaultDependencies does.
type devices struct {
	detector *detector
	svc      *storageutil.StorageService
	registry vfs.Registry
}

func newDevices(t testing.TB, mounts ...mount) devices {
	t.Helper()
	d := &detector{}
	d.set(mounts...)
	svc := storageutil.NewStorageService(d)
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
	return devices{detector: d, svc: svc, registry: registry}
}

// fsys is the files namespace of the device with serial.
func (d devices) fsys(t testing.TB, serial string) vfs.VFS {
	t.Helper()
	fsys, ok := d.registry.Get(vfs.FilesNamespace(serial))
	if !ok {
		t.Fatalf("no namespace for serial %q", serial)
	}
	return fsys
}

// makeDir creates a directory and returns the path.
func makeDir(t testing.TB, parent, name string) string {
	t.Helper()
	path := filepath.Join(parent, name)
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("makeDir: %v", err)
	}
	return path
}

// makeFile creates a file with empty contents and returns its path.
func makeFile(t testing.TB, dir, name string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatalf("makeFile: %v", err)
	}
	return path
}

// relPaths is the sorted relative paths of a search result.
func relPaths(files []IndexedFile) []string {
	out := make([]string, len(files))
	for i, f := range files {
		out[i] = f.RelPath
	}
	slices.Sort(out)
	return out
}

// waitFor polls until cond holds, failing after a few seconds.
func waitFor(t *testing.T, cond func() bool, what string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}
