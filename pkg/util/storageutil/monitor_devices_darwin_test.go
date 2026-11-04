//go:build darwin

package storageutil

import "testing"

// TestMonitorUsbDevicesReportsMountedExternals checks the live volumes the
// monitor polls. Each one has the serial and mount path the mounted-set
// comparison needs. An internal disk is not in the list.
func TestMonitorUsbDevicesReportsMountedExternals(t *testing.T) {
	devices, err := MonitorUsbDevices()
	if err != nil {
		t.Fatal(err)
	}
	for _, device := range devices {
		if device.GetSerial() == "" || device.GetMountPath() == "" {
			t.Errorf("serial %q mount %q path %q", device.GetSerial(), device.GetMountPath(), device.GetPath())
		}
		if device.GetMountPath() == "/" || device.GetMountPath() == "/System/Volumes/Data" {
			t.Errorf("internal mount %s reported as USB", device.GetMountPath())
		}
	}
}
