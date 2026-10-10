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

// bytesFromStatfs reports total, used, and available bytes for one filesystem.
//
// Used is (blocks - free) * blockSize, matching health and gopsutil, not df's
// available column. Available stays Bavail * blockSize, the space a write can
// actually use. Root-reserved blocks sit in neither figure, so they are not
// shown as used twice, and used + available is not total.
func bytesFromStatfs(blocks, free, available, blockSize uint64) (total, used, avail uint64) {
	total = blocks * blockSize
	used = (blocks - free) * blockSize
	avail = available * blockSize
	return total, used, avail
}

func detectDevices(categorize bool) ([]Device, error) {
	devices := []Device{}

	rootDevice, err := detectRootDevice(DataFilesystemPath(), categorize)
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
			sizeBytes, usedBytes, availableBytes := bytesFromStatfs(
				stat.Blocks,
				stat.Bfree,
				stat.Bavail,
				uint64(stat.Bsize),
			)

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

// parseProcMountsFor scans /proc/mounts-formatted content from r and returns
// the device path and filesystem type of the mount holding path: the longest
// mount point that is path or one of its parents. Of several mounts stacked on
// one mount point the last wins, being the one statfs measures. Both are empty
// when no mount holds path.
func parseProcMountsFor(r io.Reader, path string) (devicePath, fsType string, err error) {
	longest := -1
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 3 {
			continue
		}
		// /proc/mounts fields: device mountPoint fsType options dump pass
		// ponytail: a mount point with a space in it is written "\040" here and
		// never matches, so the next mount up is reported; unescape if that bites.
		mountPoint := fields[1]
		if len(mountPoint) >= longest && (mountPoint == "/" || within(mountPoint, path)) {
			devicePath, fsType, longest = fields[0], fields[2], len(mountPoint)
		}
	}
	return devicePath, fsType, scanner.Err()
}

// detectRootDevice describes the internal device: the filesystem holding
// dataPath, an existing path that DataFilesystemPath resolves from the data
// directory. That is the root filesystem on the appliance and a mount of its
// own when a volume is mounted over the data directory, as in a container
// (#2467). The device, filesystem type and sizes all come from that one
// filesystem. MountPoint stays "/" whichever it is, because that is how
// GetDataDirForDevice and the managed-device lookups recognize the internal
// device.
func detectRootDevice(dataPath string, categorize bool) (*Device, error) {
	f, err := os.Open("/proc/mounts")
	if err != nil {
		return nil, fmt.Errorf("failed to open /proc/mounts: %w", err)
	}
	defer f.Close()

	rootSource, rootFsType, err := parseProcMountsFor(f, dataPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read /proc/mounts: %w", err)
	}
	if rootSource == "" {
		return nil, nil // coverage: ignore - root mount always present on Linux
	}

	var stat syscall.Statfs_t
	if err := syscall.Statfs(dataPath, &stat); err != nil {
		return nil, fmt.Errorf("failed to stat the filesystem holding %s: %w", dataPath, err)
	}

	totalBytes, usedBytes, availableBytes := bytesFromStatfs(
		stat.Blocks,
		stat.Bfree,
		stat.Bavail,
		uint64(stat.Bsize),
	)

	// Not stored on Device. This ratio is used/total. df's Use% divides by
	// used plus available instead, which is a different number.
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
