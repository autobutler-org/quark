//go:build linux

package storageutil

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func TestPartitionMountCommandDoesNotPromptForSudoPassword(t *testing.T) {
	cmd := (&partition{path: "/dev/nonexistent_test_device"}).MountCommand("/mnt/test")
	if !slices.Equal(cmd.Args, []string{"sudo", "-n", "mount", "/dev/nonexistent_test_device", "/mnt/test"}) {
		t.Fatalf("MountCommand args = %q, want non-interactive sudo", cmd.Args)
	}
}

func TestFindMountPath_RootDevice(t *testing.T) {
	// The root device should always be mounted on Linux.
	// Read /proc/mounts to find the root device path first.
	data, err := os.ReadFile("/proc/mounts")
	if err != nil {
		t.Fatalf("failed to read /proc/mounts: %v", err)
	}

	var rootDev string
	for line := range strings.SplitSeq(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[1] == "/" {
			rootDev = fields[0]
			break
		}
	}
	if rootDev == "" {
		t.Skip("could not find root device in /proc/mounts")
	}

	mountPath, err := findMountPath(rootDev)
	if err != nil {
		t.Fatalf("findMountPath(%q) returned error: %v", rootDev, err)
	}
	if mountPath != "/" {
		t.Errorf("findMountPath(%q) = %q, want /", rootDev, mountPath)
	}
}

func TestFindMountPath_NonexistentDevice(t *testing.T) {
	_, err := findMountPath("/dev/nonexistent_device_xyz")
	if err == nil {
		t.Error("findMountPath for nonexistent device should return error")
	}
}

func TestResolveDevicePath_NonDevPath(t *testing.T) {
	// Non-/dev/ paths should be returned as-is.
	result, err := resolveDevicePath("/tmp/something")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != "/tmp/something" {
		t.Errorf("resolveDevicePath(/tmp/something) = %q, want /tmp/something", result)
	}
}

func TestResolveDevicePath_RegularDevPath(t *testing.T) {
	// A /dev/ path that is not a symlink should be returned as-is.
	// /dev/null always exists and is not a symlink.
	result, err := resolveDevicePath("/dev/null")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != "/dev/null" {
		t.Errorf("resolveDevicePath(/dev/null) = %q, want /dev/null", result)
	}
}

func TestResolveDevicePath_NonexistentDevPath(t *testing.T) {
	// A nonexistent /dev/ path should be returned as-is (not an error).
	result, err := resolveDevicePath("/dev/nonexistent_xyz_123")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != "/dev/nonexistent_xyz_123" {
		t.Errorf("resolveDevicePath returned %q, want /dev/nonexistent_xyz_123", result)
	}
}

func TestPartition_MountPath_UsesResolvedPaths(t *testing.T) {
	// Verify that partition.MountPath() delegates to findMountPath.
	// Use a device that definitely isn't mounted.
	p := &partition{path: "/dev/nonexistent_test_device"}
	_, err := p.MountPath()
	if err == nil {
		t.Error("MountPath for nonexistent device should return error")
	}
	if !strings.Contains(err.Error(), "not mounted") {
		t.Errorf("error should mention 'not mounted', got: %v", err)
	}
}

func TestUdevFsType(t *testing.T) {
	sys, udev := t.TempDir(), t.TempDir()
	for name, dev := range map[string]string{"sda1": "8:1", "sda2": "8:2", "sda3": "8:3"} {
		if err := os.MkdirAll(filepath.Join(sys, name), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(sys, name, "dev"), []byte(dev+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// sda1 is a Microsoft reserved partition: udev records no ID_FS_TYPE.
	if err := os.WriteFile(filepath.Join(udev, "b8:1"), []byte("E:ID_PART_ENTRY_TYPE=e3c9e316\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(udev, "b8:2"), []byte("S:disk/by-uuid/1234\nE:ID_FS_TYPE=exfat\nE:ID_FS_USAGE=filesystem\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	// sda3 has no udev record at all, as in a container without udev.
	for name, want := range map[string]string{"sda1": "", "sda2": "exfat", "sda3": "", "sdz9": ""} {
		if got := udevFsType(sys, udev, name); got != want {
			t.Errorf("udevFsType(%s) = %q, want %q", name, got, want)
		}
	}
}
