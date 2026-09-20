package storageutil

import (
	"math"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// TestDetectDevicesMatchesDfCapacity checks the reported usage against df's own
// Capacity column on this machine: APFS volumes share a container, so a
// per-volume Used ratio understates real fullness (issue #1711).
func TestDetectDevicesMatchesDfCapacity(t *testing.T) {
	devices, err := NewDetector().DetectDevices()
	if err != nil {
		t.Skipf("df unavailable: %v", err)
	}

	seen := map[string]bool{}
	for _, device := range devices {
		if device.TotalBytes == 0 {
			continue
		}
		container := (&detector{}).getContainerID(device.DevicePath)
		if seen[container] {
			t.Errorf("container %s reported twice (%s)", container, device.DevicePath)
		}
		seen[container] = true

		if device.UsedBytes+device.AvailableBytes != device.TotalBytes {
			t.Errorf("%s: used (%d) + avail (%d) != total (%d)", device.MountPoint,
				device.UsedBytes, device.AvailableBytes, device.TotalBytes)
		}

		want := dfCapacity(t, device.MountPoint)
		got := float64(device.UsedBytes) / float64(device.TotalBytes) * 100
		if math.Abs(got-want) > 1.5 {
			t.Errorf("%s: reported %.1f%% used, df says %.0f%%", device.MountPoint, got, want)
		}
	}
}

// DetectRoots stands in for DetectDevices on every file request, so it has to
// find the same volumes on this machine, including the disk images #2135
// drops and the internal flag diskutil info reports (#2195).
func TestDetectRootsMatchesDetectDevices(t *testing.T) {
	d := &detector{}
	full, err := d.DetectDevices()
	if err != nil {
		t.Skipf("df unavailable: %v", err)
	}
	roots, err := d.DetectRoots()
	if err != nil {
		t.Fatalf("DetectRoots() error = %v", err)
	}

	// Every field the file, VFS and access paths read off a managed device:
	// FilesDir and DataDir derive from MountPoint, and Name reaches the client
	// as a file's device name.
	type root struct {
		name, devicePath, mountPoint string
		isInternal                   bool
		serial                       string
	}
	summarize := func(devices []Device) []root {
		out := make([]root, 0, len(devices))
		for _, device := range devices {
			serial := ""
			if device.UsbInfo != nil {
				serial = device.UsbInfo.GetSerial()
			}
			out = append(out, root{device.Name, device.DevicePath, device.MountPoint, device.IsInternal, serial})
		}
		return out
	}
	want, got := summarize(full), summarize(roots)
	t.Logf("DetectDevices: %+v", want)
	t.Logf("DetectRoots:   %+v", got)
	if !slices.Equal(got, want) {
		t.Errorf("DetectRoots() = %+v, want %+v", got, want)
	}
}

func TestParseDiskutilList(t *testing.T) {
	const listing = `/dev/disk0 (internal, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *1.0 TB     disk0
   2:                 Apple_APFS Container disk3         994.7 GB   disk0s2

/dev/disk3 (synthesized):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      APFS Container Scheme -                      +994.7 GB   disk3
                                 Physical Store disk0s2
   1:                APFS Volume Macintosh HD            12.6 GB    disk3s1
   2:              APFS Snapshot com.apple.os.update-... 12.6 GB    disk3s1s1
   5:                APFS Volume Data                    863.7 GB   disk3s5

/dev/disk4 (disk image):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        +18.1 GB    disk4
   1:                 Apple_APFS Container disk5         18.1 GB    disk4s1

/dev/disk5 (synthesized):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      APFS Container Scheme -                      +18.1 GB    disk5
                                 Physical Store disk4s1
   1:                APFS Volume iOS 26.5 Simulator      17.6 GB    disk5s1

/dev/disk6 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *64.0 GB    disk6
   1:               Windows_NTFS USB                     64.0 GB    disk6s1
`
	disks := parseDiskutilList(listing)
	tests := []struct {
		disk                    string
		wantInternal, wantImage bool
	}{
		{"disk3", true, false},  // internal APFS container
		{"disk5", false, true},  // simulator runtime image
		{"disk6", false, false}, // USB drive
	}
	for _, tt := range tests {
		disk, ok := disks.physical(tt.disk)
		if !ok {
			t.Errorf("%s: not found", tt.disk)
			continue
		}
		if disk.isInternal != tt.wantInternal || disk.isImage != tt.wantImage {
			t.Errorf("%s: internal=%v image=%v, want internal=%v image=%v",
				tt.disk, disk.isInternal, disk.isImage, tt.wantInternal, tt.wantImage)
		}
	}
	if _, ok := disks.physical("disk9"); ok {
		t.Error("disk9: found a disk diskutil did not list")
	}

	// A file listing reports the volume name, so it has to survive the
	// space-padded columns, and a truncated one falls back to the mount point.
	names := []struct {
		devicePath, mountPoint, want string
	}{
		{"/dev/disk3s5", "/System/Volumes/Data", "Data"},
		{"/dev/disk3s1", "/", "Macintosh HD"},
		{"/dev/disk5s1", "/Library/Developer/CoreSimulator/Volumes/iOS_23F77", "iOS 26.5 Simulator"},
		{"/dev/disk6s1", "/Volumes/USB", "USB"},
		{"/dev/disk3s1s1", "/", "Macintosh HD"},     // truncated name, root mount point
		{"/dev/disk8s9", "/Volumes/Spare", "Spare"}, // unlisted volume
	}
	for _, tt := range names {
		if got := volumeName(disks.name(tt.devicePath), tt.mountPoint); got != tt.want {
			t.Errorf("%s: name = %q, want %q", tt.devicePath, got, tt.want)
		}
	}
}

func dfCapacity(t *testing.T, mountPoint string) float64 {
	t.Helper()
	out, err := exec.Command("df", "-k", mountPoint).Output()
	if err != nil {
		t.Fatalf("df %s: %v", mountPoint, err)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	fields := strings.Fields(lines[len(lines)-1])
	pct, err := strconv.ParseFloat(strings.TrimSuffix(fields[4], "%"), 64)
	if err != nil {
		t.Fatalf("parse capacity %q: %v", fields[4], err)
	}
	return pct
}

// TestIsDiskImage checks that mounted disk images, like Xcode's simulator
// runtimes, are told apart from real disks (issue #2130).
func TestIsDiskImage(t *testing.T) {
	const simulatorRuntime = `   Device Identifier:         disk5s1
   Device Node:               /dev/disk5s1
   Whole:                     No
   Part of Whole:             disk5

   Volume Name:               iOS 26.5 Simulator
   Mounted:                   Yes
   Mount Point:               /Library/Developer/CoreSimulator/Volumes/iOS_23F77

   File System Personality:   APFS
   Type (Bundle):             apfs
   Media Type:                Generic
   Protocol:                  Disk Image
   SMART Status:              Not Supported

   Disk Size:                 18.1 GB (18083741696 Bytes) (exactly 35319808 512-Byte-Units)
   Device Location:           External
   Removable Media:           Removable
`
	const internalDisk = `   Device Identifier:         disk3s5
   Device Node:               /dev/disk3s5
   Whole:                     No
   Part of Whole:             disk3

   Volume Name:               Data
   Mounted:                   Yes
   Mount Point:               /System/Volumes/Data

   File System Personality:   APFS
   Type (Bundle):             apfs
   Media Type:                Generic
   Protocol:                  Apple Fabric
   SMART Status:              Verified

   Disk Size:                 994.7 GB (994662584320 Bytes) (exactly 1942700360 512-Byte-Units)
   Device Location:           Internal
   Removable Media:           Fixed
`
	tests := []struct {
		name string
		info string
		want bool
	}{
		{"simulator runtime", simulatorRuntime, true},
		{"internal disk", internalDisk, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isDiskImage(tt.info); got != tt.want {
				t.Errorf("isDiskImage() = %v, want %v", got, tt.want)
			}
		})
	}
}
