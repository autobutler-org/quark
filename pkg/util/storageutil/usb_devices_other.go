//go:build !linux && !darwin

package storageutil

// ListUsbDevices returns an empty list on unsupported platforms.
// USB device enumeration via /sys/bus/usb/devices/ is Linux-only.
func ListUsbDevices(onlyStorage bool) ([]UsbDevice, error) {
	return []UsbDevice{}, nil
}

// MonitorUsbDevices returns an empty list where there is no sysfs USB tree
// and no mounted external volumes to watch. That is an empty list, not an
// error (#1280).
func MonitorUsbDevices() ([]UsbDevice, error) {
	return []UsbDevice{}, nil
}
