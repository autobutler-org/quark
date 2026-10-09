package trashutil_test

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/trashutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// serialUsb implements only GetSerial; any other call panics on the nil
// embedded interface.
type serialUsb struct {
	storageutil.UsbDevice
	serial string
}

func (u serialUsb) GetSerial() string { return u.serial }

type detector struct{ devices []storageutil.Device }

func (d detector) DetectDevices() ([]storageutil.Device, error) { return d.devices, nil }

// fixture is an internal drive and a USB drive with serial "A", each with a
// file at docs/a.txt, and a registry holding both namespaces.
type fixture struct {
	registry    vfs.Registry
	internalDir string
	usbDir      string
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	internal, usb := t.TempDir(), t.TempDir()
	svc := storageutil.NewStorageService(detector{devices: []storageutil.Device{
		{Name: "Internal", MountPoint: internal, IsInternal: true},
		{Name: "USB", MountPoint: usb, UsbInfo: serialUsb{serial: "A"}},
	}})
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewStorageServiceVFS(svc, "files")); err != nil {
		t.Fatal(err)
	}
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}
	f := fixture{
		registry:    registry,
		internalDir: filepath.Join(internal, "quark", "data", "files"),
		usbDir:      filepath.Join(usb, "quark", "data", "files"),
	}
	for _, dir := range []string{f.internalDir, f.usbDir} {
		if err := os.MkdirAll(filepath.Join(dir, "docs"), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "docs", "a.txt"), []byte("a"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return f
}

func (f fixture) device(serial string) trashutil.Device {
	return trashutil.Device{Registry: f.registry, Serial: serial}
}

// drain returns every event published so far.
func drain(events <-chan eventbus.Event) []eventbus.Event {
	var out []eventbus.Event
	for {
		select {
		case e := <-events:
			out = append(out, e)
		case <-time.After(50 * time.Millisecond):
			return out
		}
	}
}

func kinds(events []eventbus.Event) []string {
	out := make([]string, len(events))
	for i, e := range events {
		out[i] = string(e.Kind) + "@" + e.DeviceSerial
	}
	return out
}

// TestRestoreAndDeletePublishWithTheSerial checks a device's trash is reached
// through its namespace and every event carries the device's serial (#2641).
func TestRestoreAndDeletePublishWithTheSerial(t *testing.T) {
	f := newFixture(t)
	bus := eventbus.New()
	events, unsub := bus.Subscribe("trashutil-test")
	defer unsub()

	trashed, err := trashutil.Trash(trashutil.TrashParams{Device: f.device("A"), Paths: []string{"docs/a.txt"}, TrashedBy: 3})
	if err != nil {
		t.Fatal(err)
	}
	if len(trashed.Trashed) != 1 {
		t.Fatalf("trashed = %+v", trashed)
	}
	if _, err := os.Stat(filepath.Join(f.internalDir, "docs", "a.txt")); err != nil {
		t.Errorf("trashing on A touched the internal drive: %v", err)
	}
	name := trashed.Trashed[0].TrashName

	read, err := trashutil.ReadEntry(trashutil.ReadEntryParams{Device: f.device("A"), TrashName: name})
	if err != nil || read.Entry.TrashedBy != 3 {
		t.Fatalf("ReadEntry = %+v, %v", read, err)
	}

	restored, err := trashutil.Restore(trashutil.RestoreParams{
		Device: f.device("A"), Items: []vfs.TrashRef{{TrashName: name}}, EventBus: bus,
	})
	if err != nil || len(restored.Restored) != 1 {
		t.Fatalf("Restore = %+v, %v", restored, err)
	}
	if got, want := kinds(drain(events)), []string{"upload@A", "trash_changed@A"}; !slices.Equal(got, want) {
		t.Errorf("restore published %v, want %v", got, want)
	}

	trashed, err = trashutil.Trash(trashutil.TrashParams{Device: f.device("A"), Paths: []string{"docs/a.txt"}})
	if err != nil {
		t.Fatal(err)
	}
	deleted, err := trashutil.Delete(trashutil.DeleteParams{
		Device: f.device("A"), Items: []vfs.TrashRef{{TrashName: trashed.Trashed[0].TrashName}}, EventBus: bus,
	})
	if err != nil || deleted.Deleted != 1 {
		t.Fatalf("Delete = %+v, %v", deleted, err)
	}
	if got, want := kinds(drain(events)), []string{"trash_changed@A"}; !slices.Equal(got, want) {
		t.Errorf("delete published %v, want %v", got, want)
	}

	// An empty trash changes nothing and says nothing.
	emptied, err := trashutil.Empty(trashutil.EmptyParams{Device: f.device("A"), EventBus: bus})
	if err != nil || emptied.Deleted != 0 {
		t.Fatalf("Empty = %+v, %v", emptied, err)
	}
	if got := drain(events); len(got) != 0 {
		t.Errorf("emptying an empty trash published %v", kinds(got))
	}
}

// TestUnknownSerialIsDeviceNotFound checks a serial with no namespace never
// falls back to the internal drive's trash.
func TestUnknownSerialIsDeviceNotFound(t *testing.T) {
	f := newFixture(t)
	_, err := trashutil.Trash(trashutil.TrashParams{Device: f.device("NOPE"), Paths: []string{"docs/a.txt"}})
	if !errors.Is(err, storageutil.ErrDeviceNotFound) {
		t.Fatalf("Trash on an unknown serial = %v, want ErrDeviceNotFound", err)
	}
	if _, err := os.Stat(filepath.Join(f.internalDir, "docs", "a.txt")); err != nil {
		t.Errorf("the internal drive's file moved: %v", err)
	}
	_, err = trashutil.List(trashutil.ListParams{Device: trashutil.Device{Serial: "NOPE"}})
	if !errors.Is(err, storageutil.ErrDeviceNotFound) {
		t.Errorf("List with no registry = %v, want ErrDeviceNotFound", err)
	}
}

// TestNamespaceWithoutTrash checks a namespace that cannot trash says so
// rather than deleting for good.
func TestNamespaceWithoutTrash(t *testing.T) {
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewMemVFS("files")); err != nil {
		t.Fatal(err)
	}
	_, err := trashutil.List(trashutil.ListParams{Device: trashutil.Device{Registry: registry}})
	if !errors.Is(err, trashutil.ErrNoTrash) {
		t.Fatalf("List on a MemVFS = %v, want ErrNoTrash", err)
	}
}

// TestPurgeExpiredSweepsEveryDevice checks the hourly purge reaches every
// device namespace and reports each removal with its serial.
func TestPurgeExpiredSweepsEveryDevice(t *testing.T) {
	f := newFixture(t)
	bus := eventbus.New()
	events, unsub := bus.Subscribe("trashutil-purge-test")
	defer unsub()
	for _, serial := range []string{"", "A"} {
		if _, err := trashutil.Trash(trashutil.TrashParams{Device: f.device(serial), Paths: []string{"docs/a.txt"}}); err != nil {
			t.Fatal(err)
		}
	}

	result, err := trashutil.PurgeExpired(trashutil.PurgeExpiredParams{Registry: f.registry, EventBus: bus})
	if err != nil || result.Purged != 0 {
		t.Fatalf("a fresh trash was purged: %+v, %v", result, err)
	}

	later := time.Now().AddDate(0, 0, storageutil.TrashRetentionDays+1)
	result, err = trashutil.PurgeExpired(trashutil.PurgeExpiredParams{Registry: f.registry, EventBus: bus, Now: later})
	if err != nil {
		t.Fatal(err)
	}
	serials := make([]string, 0, len(result.Removed))
	for _, r := range result.Removed {
		serials = append(serials, r.DeviceSerial)
	}
	slices.Sort(serials)
	if result.Purged != 2 || !slices.Equal(serials, []string{"", "A"}) {
		t.Fatalf("PurgeExpired = %+v, want one item on each device", result)
	}
	got := kinds(drain(events))
	slices.Sort(got)
	if want := []string{"trash_changed@", "trash_changed@A"}; !slices.Equal(got, want) {
		t.Errorf("purge published %v, want %v", got, want)
	}
}
