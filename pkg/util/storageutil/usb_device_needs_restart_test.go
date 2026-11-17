package storageutil

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// fakeUsbDisk lays out a sysfs tree in which USB device "2-1" owns block
// device "sda", the way the kernel shows a drive to a container that started
// before it was plugged in: sysfs is live, /dev is the copy taken at start and
// holds no sda (#4018). It points sysBlockDir and devDir at the fake tree for
// the test and returns the device and the fake /dev.
func fakeUsbDisk(t *testing.T) (*usbDevice, string) {
	t.Helper()
	root := t.TempDir()
	usbPath := filepath.Join(root, "sys", "devices", "usb1", "2-1")
	scsiDevice := filepath.Join(usbPath, "2-1:1.0", "host0", "target0:0:0", "0:0:0:0")
	sysBlock := filepath.Join(root, "sys", "block")
	dev := filepath.Join(root, "dev")
	for _, dir := range []string{scsiDevice, filepath.Join(sysBlock, "sda"), dev} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(scsiDevice, filepath.Join(sysBlock, "sda", "device")); err != nil {
		t.Fatal(err)
	}

	savedSys, savedDev := sysBlockDir, devDir
	t.Cleanup(func() { sysBlockDir, devDir = savedSys, savedDev })
	sysBlockDir, devDir = sysBlock, dev

	return &usbDevice{Path: usbPath, Manufacturer: "Fake", Product: "Drive", Serial: "2641R5D03639"}, dev
}

// A drive sysfs shows but /dev does not needs a restart, and mounting it
// fails with that before any mount command runs, rather than with mount's
// "special device /dev/sda does not exist" (#4018).
func TestUsbDevice_NoDevNodeNeedsRestart(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	device, _ := fakeUsbDisk(t)

	if !device.IsStorageDevice() {
		t.Fatal("the fake disk is not seen as a storage device")
	}
	if !DeviceNeedsRestart(device) {
		t.Error("DeviceNeedsRestart = false for a disk with no /dev node")
	}
	if _, err := device.Partitions(); !errors.Is(err, ErrNeedsRestart) {
		t.Errorf("Partitions error = %v, want ErrNeedsRestart", err)
	}
	result, err := AutoMountDevice(device)
	if !errors.Is(err, ErrNeedsRestart) {
		t.Errorf("AutoMountDevice error = %v, want ErrNeedsRestart", err)
	}
	if result != nil {
		t.Errorf("AutoMountDevice result = %+v, want none", result)
	}
}

// Once /dev has the node, the same drive is an ordinary mountable one.
func TestUsbDevice_DevNodePresentIsMountable(t *testing.T) {
	device, dev := fakeUsbDisk(t)
	if err := os.WriteFile(filepath.Join(dev, "sda"), nil, 0o644); err != nil {
		t.Fatal(err)
	}

	if DeviceNeedsRestart(device) {
		t.Error("DeviceNeedsRestart = true for a disk whose /dev node exists")
	}
	partitions, err := device.Partitions()
	if err != nil {
		t.Fatalf("Partitions: %v", err)
	}
	if len(partitions) != 1 || partitions[0].Path() != filepath.Join(dev, "sda") {
		t.Errorf("Partitions = %v, want the whole disk", paths(partitions))
	}
}

// A partition the kernel added after start (the drive was repartitioned) is
// missing from /dev too, even when the disk's own node is there.
func TestUsbDevice_MissingPartitionNodeNeedsRestart(t *testing.T) {
	device, dev := fakeUsbDisk(t)
	if err := os.WriteFile(filepath.Join(dev, "sda"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	part := filepath.Join(sysBlockDir, "sda", "sda1")
	if err := os.MkdirAll(part, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(part, "partition"), []byte("1\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if !DeviceNeedsRestart(device) {
		t.Error("DeviceNeedsRestart = false for a partition with no /dev node")
	}
	if _, err := device.Partitions(); !errors.Is(err, ErrNeedsRestart) {
		t.Errorf("Partitions error = %v, want ErrNeedsRestart", err)
	}
}

// Devices with no block device at all are not storage, and never need a
// restart on that account.
func TestDeviceNeedsRestart_NoBlockDevice(t *testing.T) {
	if DeviceNeedsRestart(unmountedDevice{}) {
		t.Error("a fake device whose Partitions succeed reported needing a restart")
	}
}
