//go:build linux

package storageutil

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
)

// usbDevicesPath is the sysfs directory the kernel exposes USB devices under.
// It is a var so tests can point enumeration at a directory that does not exist.
var usbDevicesPath = "/sys/bus/usb/devices/"

// ListUsbDevices lists all USB devices under /sys/bus/usb/devices/
func ListUsbDevices(onlyStorage bool) ([]UsbDevice, error) {
	base := usbDevicesPath
	entries, err := os.ReadDir(base)
	if errors.Is(err, fs.ErrNotExist) {
		// The kernel was built without USB support, so there is no USB
		// subsystem to enumerate — WSL2, minimal VMs, containers with a
		// restricted /sys. That is an empty device list, not a failure, and
		// reporting it as one floods the log on every poll (#1788). The darwin
		// and other-platform builds already return empty for the same reason.
		return []UsbDevice{}, nil
	}
	if err != nil {
		return nil, err
	}
	var devices []UsbDevice
	for _, entry := range entries {
		devicePath := filepath.Join(base, entry.Name())
		vendor := readFileTrim(filepath.Join(devicePath, "idVendor"))
		product := readFileTrim(filepath.Join(devicePath, "idProduct"))
		if vendor == "" || product == "" {
			continue // Not a device directory
		}
		dev := &usbDevice{
			Path:         devicePath,
			VendorID:     vendor,
			ProductID:    product,
			Manufacturer: readFileTrim(filepath.Join(devicePath, "manufacturer")),
			Product:      readFileTrim(filepath.Join(devicePath, "product")),
			Serial:       readFileTrim(filepath.Join(devicePath, "serial")),
		}
		if dev.IsStorageDevice() {
			// Best-effort: UpdateStatus clears MountPath when the mount check
			// fails, so an unreadable device is reported unmounted rather than
			// aborting the enumeration of every other device.
			_ = dev.UpdateStatus()
		} else if onlyStorage {
			continue
		}
		devices = append(devices, dev)
	}
	return devices, nil
}
