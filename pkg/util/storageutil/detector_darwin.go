package storageutil

import (
	"bufio"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var snapshotRegex = regexp.MustCompile(`/dev/disk\d+s\d+s\d+`)

// detector implements storage detection for macOS
type detector struct{}

func NewDetector() Detector {
	return &detector{}
}

// dfVolume is one line of `df -k` for a disk that device detection considers:
// a /dev/disk volume that is neither a hidden system volume nor an APFS
// snapshot.
type dfVolume struct {
	devicePath string
	mountPoint string
	totalKB    uint64
	usedKB     uint64
	availKB    uint64
}

// listDfVolumes runs `df -k` and returns the volumes device detection
// considers. READ ONLY.
func listDfVolumes() ([]dfVolume, error) {
	output, err := exec.Command("df", "-k").Output()
	if err != nil {
		return nil, fmt.Errorf("failed to run df: %w", err)
	}

	var volumes []dfVolume
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	scanner.Scan() // Skip header
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 6 {
			continue
		}
		devicePath := fields[0]
		mountPoint := fields[len(fields)-1]
		// Skip non-disk filesystems, system volumes we don't want to show,
		// and APFS snapshot devices
		if !strings.HasPrefix(devicePath, "/dev/disk") || shouldSkipVolume(mountPoint) ||
			snapshotRegex.MatchString(devicePath) {
			continue
		}
		// Sizes from df are in KB
		totalKB, _ := strconv.ParseUint(fields[1], 10, 64)
		usedKB, _ := strconv.ParseUint(fields[2], 10, 64)
		availKB, _ := strconv.ParseUint(fields[3], 10, 64)
		volumes = append(volumes, dfVolume{
			devicePath: devicePath,
			mountPoint: mountPoint,
			totalKB:    totalKB,
			usedKB:     usedKB,
			availKB:    availKB,
		})
	}
	return volumes, nil
}

// DetectDevices finds all storage devices on macOS using read-only commands
func (d *detector) DetectDevices() ([]Device, error) {
	devices := []Device{}
	seenContainers := make(map[string]bool) // Track APFS containers to avoid double-counting

	volumes, err := listDfVolumes()
	if err != nil {
		return devices, err
	}

	for _, volume := range volumes {
		// Get detailed device info
		device, err := d.getDeviceInfo(volume.devicePath)
		if err != nil {
			continue // Skip devices we can't read
		}

		// Only report one volume per APFS container: siblings share the same
		// physical space, so listing each one double-counts the container.
		containerID := d.getContainerID(volume.devicePath)
		if containerID != "" {
			if seenContainers[containerID] {
				continue
			}
			seenContainers[containerID] = true
		}

		// Override with df values which are more accurate.
		// APFS volumes in one container share Size/Avail but report a
		// per-volume Used, so derive Used from the shared free space instead
		// (this matches df's own Capacity column).
		device.TotalBytes = volume.totalKB * 1024
		device.AvailableBytes = volume.availKB * 1024
		if volume.totalKB > volume.availKB {
			device.UsedBytes = (volume.totalKB - volume.availKB) * 1024
		} else {
			device.UsedBytes = volume.usedKB * 1024
		}
		device.MountPoint = volume.mountPoint

		// Apply simple categorization for UI
		device.ApplySimpleCategorization()

		devices = append(devices, *device)
	}

	return devices, nil
}

// DetectRoots returns the volumes DetectDevices would, with DevicePath,
// MountPoint, IsInternal and Name set. One `diskutil list` stands in for the
// `diskutil info` per volume and the categorization walk, since it names each
// volume and each whole disk's location and whether it is a disk image (#2195).
func (d *detector) DetectRoots() ([]Device, error) {
	volumes, err := listDfVolumes()
	if err != nil {
		return []Device{}, err
	}
	output, err := exec.Command("diskutil", "list").Output()
	if err != nil {
		return []Device{}, fmt.Errorf("failed to run diskutil list: %w", err)
	}
	disks := parseDiskutilList(string(output))

	devices := []Device{}
	seenContainers := make(map[string]bool)
	for _, volume := range volumes {
		containerID := d.getContainerID(volume.devicePath)
		disk, ok := disks.physical(containerID)
		if !ok || disk.isImage {
			// Unknown to diskutil, or a mounted disk image (#2135). A container
			// sits on one physical store, so its volumes are all images or
			// none, and skipping before dedup matches DetectDevices.
			continue
		}
		if seenContainers[containerID] {
			continue
		}
		seenContainers[containerID] = true
		devices = append(devices, Device{
			DevicePath: volume.devicePath,
			MountPoint: volume.mountPoint,
			IsInternal: disk.isInternal,
			// The same fallbacks getDeviceInfo applies to a volume diskutil
			// leaves unnamed. A file listing reports this name (#2195).
			Name: volumeName(disks.name(volume.devicePath), volume.mountPoint),
		})
	}
	return devices, nil
}

// getContainerID extracts the APFS container identifier from device path
// e.g., /dev/disk3s1s1 -> disk3 (the base disk)
func (d *detector) getContainerID(devicePath string) string {
	// Extract base disk number (e.g., disk3 from /dev/disk3s1s1)
	re := regexp.MustCompile(`/dev/(disk\d+)`)
	matches := re.FindStringSubmatch(devicePath)
	if len(matches) > 1 {
		return matches[1]
	}
	return ""
}

// getDeviceInfo retrieves detailed information about a specific device using diskutil
func (d *detector) getDeviceInfo(devicePath string) (*Device, error) {
	device := &Device{
		DevicePath: devicePath,
	}

	// Get device info using diskutil info - READ ONLY
	cmd := exec.Command("diskutil", "info", devicePath)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get device info: %w", err)
	}

	info := string(output)
	if isDiskImage(info) {
		// Mounted .dmg files and Xcode's simulator runtimes are not storage.
		return nil, fmt.Errorf("%s is a mounted disk image", devicePath)
	}
	device.Name = extractValue(info, "Volume Name:")
	device.MountPoint = extractValue(info, "Mount Point:")
	device.FileSystem = extractValue(info, "Type \\(Bundle\\):")
	device.Model = extractValue(info, "Device / Media Name:")
	deviceLocation := extractValue(info, "Device Location:")
	if deviceLocation == "Internal" {
		device.IsInternal = true
	}

	// Parse sizes
	if totalStr := extractValue(info, "Disk Size:"); totalStr != "" {
		device.TotalBytes = parseSize(totalStr)
	}
	if availStr := extractValue(info, "Volume Free Space:"); availStr != "" {
		device.AvailableBytes = parseSize(availStr)
	}
	device.UsedBytes = device.TotalBytes - device.AvailableBytes

	// Set default name if empty
	device.Name = volumeName(device.Name, device.MountPoint)

	return device, nil
}

// Helper functions

// listedDisk is one whole disk from `diskutil list`.
type listedDisk struct {
	isInternal bool   // "internal" in the header; diskutil info's "Device Location: Internal"
	isImage    bool   // "disk image" in the header; diskutil info's "Protocol: Disk Image"
	store      string // the whole disk under a synthesized APFS container's physical store, e.g. "disk0" for "disk0s2"
}

// diskutilList is a parsed `diskutil list`: its whole disks ("disk3") and the
// name of each volume on them ("disk3s5" → "Data").
type diskutilList struct {
	disks map[string]listedDisk
	names map[string]string
}

var (
	diskutilListHeaderRegex = regexp.MustCompile(`^/dev/(disk\d+) \(([^)]*)\):`)
	diskutilListStoreRegex  = regexp.MustCompile(`Physical Store (disk\d+)`) // captures the whole disk only
	diskutilListRowRegex    = regexp.MustCompile(`^\s*\d+:\s`)
)

// parseDiskutilList parses the text of `diskutil list`. Each whole disk opens
// with a header such as "/dev/disk0 (internal, physical):" or
// "/dev/disk4 (disk image):", and a synthesized APFS container names the
// partition it lives on in a "Physical Store disk0s2" line below its header.
//
// Under each header sits a column header — "#: TYPE NAME SIZE IDENTIFIER" —
// and one row per partition or volume. Both a type and a volume name may hold
// spaces, so a row is read by the column offsets the header gives rather than
// by its fields. `diskutil list` truncates a name too wide for its column with
// an ellipsis; such a name is left out rather than reported short.
func parseDiskutilList(output string) diskutilList {
	list := diskutilList{disks: map[string]listedDisk{}, names: map[string]string{}}
	current := ""
	nameCol, sizeCol := 0, 0
	for _, line := range strings.Split(output, "\n") {
		if m := diskutilListHeaderRegex.FindStringSubmatch(line); m != nil {
			current = m[1]
			nameCol, sizeCol = 0, 0
			list.disks[current] = listedDisk{
				isInternal: strings.Contains(m[2], "internal"),
				isImage:    strings.Contains(m[2], "disk image"),
			}
			continue
		}
		if current == "" {
			continue
		}
		// A container spanning several stores (Fusion) takes the first.
		if m := diskutilListStoreRegex.FindStringSubmatch(line); m != nil && list.disks[current].store == "" {
			disk := list.disks[current]
			disk.store = m[1]
			list.disks[current] = disk
			continue
		}
		if strings.Contains(line, "IDENTIFIER") {
			nameCol, sizeCol = strings.Index(line, "NAME"), strings.Index(line, "SIZE")
			continue
		}
		if nameCol <= 0 || sizeCol <= nameCol || !diskutilListRowRegex.MatchString(line) {
			continue
		}
		fields := strings.Fields(line)
		identifier := fields[len(fields)-1]
		if len(line) < nameCol {
			continue
		}
		// A size is left-aligned under SIZE with its "+" or "*" marker hanging
		// one column to the left, so the name ends one column before SIZE.
		end := min(sizeCol-1, len(line))
		name := strings.TrimSpace(line[nameCol:end])
		if name != "" && !strings.HasSuffix(name, "...") {
			list.names[identifier] = name
		}
	}
	return list
}

// physical follows a synthesized container down to the whole disk holding its
// physical store, which is where the location and disk-image flags live.
func (list diskutilList) physical(wholeDisk string) (listedDisk, bool) {
	disk, ok := list.disks[wholeDisk]
	for hops := 0; ok && disk.store != "" && hops < 4; hops++ {
		disk, ok = list.disks[disk.store]
	}
	return disk, ok
}

// name returns the volume name diskutil listed for a device path such as
// "/dev/disk3s5", or "" when diskutil listed none or had to truncate it.
func (list diskutilList) name(devicePath string) string {
	return list.names[strings.TrimPrefix(devicePath, "/dev/")]
}

// volumeName applies the fallbacks a volume with no name of its own gets: the
// last element of its mount point, and "Macintosh HD" for the root volume.
func volumeName(name, mountPoint string) string {
	if name != "" {
		return name
	}
	name = filepath.Base(mountPoint)
	if name == "" || name == "/" {
		return "Macintosh HD"
	}
	return name
}

func shouldSkipVolume(mountPoint string) bool {
	// Skip system-internal volumes
	skipPrefixes := []string{
		"/System/Volumes/VM",
		"/System/Volumes/Preboot",
		"/System/Volumes/Update",
		"/System/Volumes/xarts",
		"/System/Volumes/iSCPreboot",
		"/System/Volumes/Hardware",
		"/private/var/vm",
		"/dev",
	}

	for _, prefix := range skipPrefixes {
		if strings.HasPrefix(mountPoint, prefix) {
			return true
		}
	}

	return false
}

// isDiskImage reports whether diskutil info text describes a mounted disk image.
func isDiskImage(info string) bool {
	return extractValue(info, "Protocol:") == "Disk Image"
}

func extractValue(info, key string) string {
	// Extract value after key using regex
	re := regexp.MustCompile(key + `\s+(.+)`)
	matches := re.FindStringSubmatch(info)
	if len(matches) > 1 {
		return strings.TrimSpace(matches[1])
	}
	return ""
}

func parseSize(sizeStr string) uint64 {
	// Parse size strings like "245.1 GB (245107195904 Bytes)"
	re := regexp.MustCompile(`\((\d+)\s+Bytes\)`)
	matches := re.FindStringSubmatch(sizeStr)
	if len(matches) > 1 {
		size, _ := strconv.ParseUint(matches[1], 10, 64)
		return size
	}
	return 0
}
