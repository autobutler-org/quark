//go:build linux

package storageutil

import (
	"path/filepath"
	"testing"
)

// TestMonitorUsbDevices_MissingSysfsIsEmpty keeps usbDeviceMonitor on the
// sysfs list. A kernel with no USB tree is an empty list, not an error the
// monitor would log on every tick (#1788, #1280).
func TestMonitorUsbDevices_MissingSysfsIsEmpty(t *testing.T) {
	original := usbDevicesPath
	t.Cleanup(func() { usbDevicesPath = original })
	usbDevicesPath = filepath.Join(t.TempDir(), "no", "usb", "here")

	devices, err := MonitorUsbDevices()
	if err != nil {
		t.Fatalf("MonitorUsbDevices() error = %v", err)
	}
	if len(devices) != 0 {
		t.Fatalf("MonitorUsbDevices() = %d devices, want none", len(devices))
	}
}
