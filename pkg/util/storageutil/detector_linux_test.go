package storageutil

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

// The /proc/mounts of the container in #2467: quark's data sits on an Azure
// Files share mounted at /var/lib/quark, not on the overlay root.
const separateDataMounts = `overlay / overlay rw,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
//storage.example.net/quark /var/lib/quark cifs rw,relatime,vers=3.0,cache=strict 0 0
tmpfs /var/lib/quark-old tmpfs rw 0 0
`

// #2467: the internal device described the root mount even when the data
// directory was a mount of its own.
func TestParseProcMountsFor_PicksTheMountHoldingThePath(t *testing.T) {
	cases := []struct {
		name       string
		path       string
		wantDevice string
		wantFsType string
	}{
		{"under a separate mount", "/var/lib/quark/data", "//storage.example.net/quark", "cifs"},
		{"the mount point itself", "/var/lib/quark", "//storage.example.net/quark", "cifs"},
		{"a sibling that only shares a name prefix", "/var/lib/quark-old/data", "tmpfs", "tmpfs"},
		{"nothing nearer than root", "/home/me/quark/data", "overlay", "overlay"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			devicePath, fsType, err := parseProcMountsFor(strings.NewReader(separateDataMounts), tc.path)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if devicePath != tc.wantDevice || fsType != tc.wantFsType {
				t.Errorf("parseProcMountsFor(%q) = %q, %q; want %q, %q",
					tc.path, devicePath, fsType, tc.wantDevice, tc.wantFsType)
			}
		})
	}
}

// #2467 end to end, on a filesystem this machine really has apart from root:
// the capacity and filesystem come from where the data directory lives, and
// the device keeps the "/" identity the managed-device lookups key on.
func TestDetectRootDevice_ReportsTheDataDirFilesystem(t *testing.T) {
	const shm = "/dev/shm"
	var rootStat, shmStat syscall.Stat_t
	if syscall.Stat("/", &rootStat) != nil || syscall.Stat(shm, &shmStat) != nil || rootStat.Dev == shmStat.Dev {
		t.Skip("no /dev/shm mounted apart from /")
	}
	var want syscall.Statfs_t
	if err := syscall.Statfs(shm, &want); err != nil {
		t.Fatalf("statfs %s: %v", shm, err)
	}

	// The data directory need not exist yet: a fresh install detects first.
	device, err := detectRootDevice(filepath.Join(shm, "quark-2467-missing", "data"), false)
	if err != nil {
		t.Fatalf("detectRootDevice() error = %v", err)
	}
	if device == nil {
		t.Fatal("detectRootDevice() = nil")
	}
	if wantTotal := want.Blocks * uint64(want.Bsize); device.TotalBytes != wantTotal {
		t.Errorf("TotalBytes = %d, want %s's %d", device.TotalBytes, shm, wantTotal)
	}
	if device.FileSystem != "tmpfs" {
		t.Errorf("FileSystem = %q, want tmpfs", device.FileSystem)
	}
	if device.MountPoint != "/" || !device.IsInternal {
		t.Errorf("MountPoint = %q, IsInternal = %v; want the internal device at /", device.MountPoint, device.IsInternal)
	}
}

func TestNearestExisting(t *testing.T) {
	target := t.TempDir()
	if resolved, err := filepath.EvalSymlinks(target); err == nil {
		target = resolved
	}
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}

	if got := nearestExisting(filepath.Join(target, "not", "yet")); got != target {
		t.Errorf("a missing path: got %q, want its existing parent %q", got, target)
	}
	if got := nearestExisting(filepath.Join(link, "not", "yet")); got != target {
		t.Errorf("a missing path behind a symlink: got %q, want %q", got, target)
	}
}

func TestParseProcMountsFor_RootFound(t *testing.T) {
	content := `sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
/dev/sda1 / ext4 rw,relatime 0 0
tmpfs /tmp tmpfs rw,nosuid,nodev 0 0
`
	devicePath, fsType, err := parseProcMountsFor(strings.NewReader(content), "/")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if devicePath != "/dev/sda1" {
		t.Errorf("expected device path '/dev/sda1', got %q", devicePath)
	}
	if fsType != "ext4" {
		t.Errorf("expected fsType 'ext4', got %q", fsType)
	}
}

func TestParseProcMountsFor_RootNotFound(t *testing.T) {
	content := `sysfs /sys sysfs rw 0 0
proc /proc proc rw 0 0
`
	devicePath, fsType, err := parseProcMountsFor(strings.NewReader(content), "/")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if devicePath != "" {
		t.Errorf("expected empty device path, got %q", devicePath)
	}
	if fsType != "" {
		t.Errorf("expected empty fsType, got %q", fsType)
	}
}

func TestParseProcMountsFor_RootSkipsMalformedLines(t *testing.T) {
	content := `tooshort
/dev/sda1 / ext4 rw,relatime 0 0
`
	devicePath, fsType, err := parseProcMountsFor(strings.NewReader(content), "/")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if devicePath != "/dev/sda1" {
		t.Errorf("expected device path '/dev/sda1', got %q", devicePath)
	}
	if fsType != "ext4" {
		t.Errorf("expected fsType 'ext4', got %q", fsType)
	}
}

func TestParseProcMountsFor_RootReturnsLastRootMount(t *testing.T) {
	// Mounts stacked on one mount point: the last covers the others, and it is
	// the one statfs measures.
	content := `none / tmpfs rw 0 0
/dev/sda1 / ext4 rw 0 0
`
	devicePath, _, err := parseProcMountsFor(strings.NewReader(content), "/")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if devicePath != "/dev/sda1" {
		t.Errorf("expected last root '/dev/sda1', got %q", devicePath)
	}
}

// Reserved blocks are neither used nor writable. Counting them as used made
// Devices disagree with Health on the same disk (#2011).
func TestBytesFromStatfs_ReservedBlocksAreNotUsed(t *testing.T) {
	total, used, available := bytesFromStatfs(1000, 400, 300, 4096)
	if total != 4096000 {
		t.Errorf("total: got %d, want 4096000", total)
	}
	if used != 2457600 {
		t.Errorf("used: got %d, want 2457600", used)
	}
	if available != 1228800 {
		t.Errorf("available: got %d, want 1228800", available)
	}
	if used+available == total {
		t.Errorf("used (%d) + available (%d) = total (%d); reserved blocks must sit in neither", used, available, total)
	}
}

func TestParseProcMountsFor_RootEmpty(t *testing.T) {
	devicePath, fsType, err := parseProcMountsFor(strings.NewReader(""), "/")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if devicePath != "" || fsType != "" {
		t.Errorf("expected empty results for empty input, got %q %q", devicePath, fsType)
	}
}
