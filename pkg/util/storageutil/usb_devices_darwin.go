//go:build darwin

package storageutil

// ListUsbDevices returns an empty list on macOS.
// USB device enumeration via /sys/bus/usb/devices/ is Linux-only.
func ListUsbDevices(onlyStorage bool) ([]UsbDevice, error) {
	return []UsbDevice{}, nil
}

// MonitorUsbDevices is what usbDeviceMonitor polls. macOS has no sysfs USB
// list, so this is the mounted external volumes DetectRoots already sees, with
// the volume UUID as the serial. An OS-mounted volume does not need
// auto-mount. A change in the set invalidates the device cache (#3957). No
// such volume is an empty list and no error, so a host without one does not
// log on every tick (#1280).
func MonitorUsbDevices() ([]UsbDevice, error) {
	roots, err := (&detector{}).DetectRoots()
	if err != nil {
		return nil, err
	}
	return externalMountedUsbDevices(roots), nil
}
