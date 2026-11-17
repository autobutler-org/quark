package storageutil

import (
	"os"
	"path/filepath"
	"testing"
)

// A kernel built without USB support has no /sys/bus/usb at all (WSL2, minimal
// VMs, containers with a restricted /sys). That must read as an empty device
// list, not an error — usbDeviceMonitor polls every 5s and logged the error on
// every tick, flooding the log forever (#1788).
func TestListUsbDevices_MissingSysfsRootIsNotAnError(t *testing.T) {
	original := usbDevicesPath
	t.Cleanup(func() { usbDevicesPath = original })
	usbDevicesPath = filepath.Join(t.TempDir(), "no", "usb", "here")

	for i := range 3 {
		devices, err := ListUsbDevices(true)
		if err != nil {
			t.Fatalf("call %d: expected no error for a missing sysfs root, got %v", i, err)
		}
		if len(devices) != 0 {
			t.Fatalf("call %d: expected no devices, got %d", i, len(devices))
		}
	}
}

// A sysfs root that exists but holds nothing device-shaped is also empty, and
// still not an error.
func TestListUsbDevices_EmptySysfsRoot(t *testing.T) {
	original := usbDevicesPath
	t.Cleanup(func() { usbDevicesPath = original })
	usbDevicesPath = t.TempDir()

	devices, err := ListUsbDevices(true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(devices) != 0 {
		t.Fatalf("expected no devices, got %d", len(devices))
	}
}

// Detection lists a drive with no /dev node as needing a restart, not as an
// ordinary unmounted drive the Mount button would fail on (#4018).
func TestDetectDevices_NoDevNodeNeedsRestart(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	device, _ := fakeUsbDisk(t)
	for name, value := range map[string]string{"idVendor": "0781", "idProduct": "55dd", "serial": device.Serial} {
		if err := os.WriteFile(filepath.Join(device.Path, name), []byte(value+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	original := usbDevicesPath
	t.Cleanup(func() { usbDevicesPath = original })
	usbDevicesPath = filepath.Dir(device.Path)

	devices, err := detectDevices(false)
	if err != nil {
		t.Fatalf("detectDevices: %v", err)
	}
	var found bool
	for _, d := range devices {
		if d.UsbInfo == nil || d.UsbInfo.GetSerial() != device.Serial {
			continue
		}
		found = true
		if !d.NeedsRestart {
			t.Error("NeedsRestart = false for a drive with no /dev node")
		}
		if d.MountPoint != "" {
			t.Errorf("MountPoint = %q, want unmounted", d.MountPoint)
		}
	}
	if !found {
		t.Fatalf("the fake drive was not detected among %d devices", len(devices))
	}
}
