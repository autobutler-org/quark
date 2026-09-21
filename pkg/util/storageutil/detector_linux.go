package storageutil

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"syscall"
)

// detector implements storage detection for Linux
type detector struct{}

func NewDetector() Detector {
	return &detector{}
}

// DetectDevices finds all storage devices on Linux using read-only commands.
//
// If a device is a USB storage device, it is enriched with USB-specific metadata
// by cross-referencing with ListUsbDevices. The UsbInfo field will be set
// if a match is found by block device path or mount point.
func (d *detector) DetectDevices() ([]Device, error) {
	return detectDevices(true)
}

// DetectRoots returns the same devices as DetectDevices without walking each
// one's files to categorize its usage, the only expensive step on Linux (#2195).
func (d *detector) DetectRoots() ([]Device, error) {
	return detectDevices(false)
}

func detectDevices(categorize bool) ([]Device, error) {
	devices := []Device{}

	rootDevice, err := detectRootDevice(categorize)
	if err != nil {
		return devices, err
	}
	if rootDevice != nil {
		devices = append(devices, *rootDevice)
	}

	// Now add USB storage devices
	usbDevices, err := ListUsbDevices(true)
	if err == nil {
		for _, usb := range usbDevices {
			name := fmt.Sprintf("%s - %s", usb.GetManufacturer(), usb.GetProduct())
			mountPath := usb.GetMountPath()
			if mountPath == "" {
				dev := Device{
					Name:           name,
					DevicePath:     "",
					MountPoint:     "",
					TotalBytes:     0,
					UsedBytes:      0,
					AvailableBytes: 0,
					IsInternal:     false,
					Model:          usb.GetProduct(),
					UsbInfo:        usb,
				}
				devices = append(devices, dev)
				continue
			}

			partitions, err := usb.Partitions()
			if err != nil || len(partitions) == 0 {
				continue
			}
			stat, err := partitions[0].Stat()
			if err != nil {
				continue
			}
			devicePath, exists := usb.BlockDevicePath()
			if !exists {
				continue
			}
			blockSize := uint64(stat.Bsize)
			sizeBytes := stat.Blocks * blockSize
			usedBytes := (stat.Blocks - stat.Bavail) * blockSize
			availableBytes := stat.Bavail * blockSize

			device := Device{
				Name:           name,
				DevicePath:     devicePath,
				MountPoint:     mountPath,
				TotalBytes:     sizeBytes,
				UsedBytes:      usedBytes,
				AvailableBytes: availableBytes,
				IsInternal:     false,
				Model:          usb.GetProduct(),
				UsbInfo:        usb,
			}
			if categorize {
				device.ApplySimpleCategorization()
			}
			devices = append(devices, device)
		}
	}

	return devices, nil
}

// parseProcMountsRoot scans /proc/mounts-formatted content from r and returns
// the device path and filesystem type for the root ("/") mount, or empty
// strings if not found.
func parseProcMountsRoot(r io.Reader) (devicePath, fsType string, err error) {
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 3 {
			continue
		}
		// /proc/mounts fields: device mountPoint fsType options dump pass
		if fields[1] == "/" {
			return fields[0], fields[2], nil
		}
	}
	return "", "", scanner.Err()
}

// detectRootDevice parses /proc/mounts to find the root filesystem mount
// and uses syscall.Statfs to get size information.
// This replaces the previous df-based approach which spawned a subprocess.
func detectRootDevice(categorize bool) (*Device, error) {
	f, err := os.Open("/proc/mounts")
	if err != nil {
		return nil, fmt.Errorf("failed to open /proc/mounts: %w", err)
	}
	defer f.Close()

	rootSource, rootFsType, err := parseProcMountsRoot(f)
	if err != nil {
		return nil, fmt.Errorf("failed to read /proc/mounts: %w", err)
	}
	if rootSource == "" {
		return nil, nil // coverage: ignore - root mount always present on Linux
	}

	var stat syscall.Statfs_t
	if err := syscall.Statfs("/", &stat); err != nil {
		return nil, fmt.Errorf("failed to stat root filesystem: %w", err)
	}

	blockSize := uint64(stat.Bsize)
	totalBytes := stat.Blocks * blockSize
	availableBytes := stat.Bavail * blockSize
	usedBytes := totalBytes - availableBytes

	// Express used/available as percentage to match original df output intent
	var pct string
	if totalBytes > 0 {
		pct = strconv.Itoa(int(usedBytes*100/totalBytes)) + "%"
	} else {
		pct = "0%"
	}
	_ = pct // available for future use in Device

	device := &Device{
		DevicePath:     rootSource,
		MountPoint:     "/",
		FileSystem:     rootFsType,
		TotalBytes:     totalBytes,
		UsedBytes:      usedBytes,
		AvailableBytes: availableBytes,
		IsInternal:     true,
	}

	device.Name = rootDeviceName(device.MountPoint)

	if categorize {
		device.ApplySimpleCategorization()
	}
	return device, nil
}
