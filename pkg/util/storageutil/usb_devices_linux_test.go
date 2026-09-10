package storageutil

import (
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
