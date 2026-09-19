package storageutil

import (
	"math"
	"os/exec"
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
