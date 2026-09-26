package storageutil

import (
	"strings"
	"testing"
)

func TestParseProcMountsRoot_Found(t *testing.T) {
	content := `sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
/dev/sda1 / ext4 rw,relatime 0 0
tmpfs /tmp tmpfs rw,nosuid,nodev 0 0
`
	devicePath, fsType, err := parseProcMountsRoot(strings.NewReader(content))
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

func TestParseProcMountsRoot_NotFound(t *testing.T) {
	content := `sysfs /sys sysfs rw 0 0
proc /proc proc rw 0 0
`
	devicePath, fsType, err := parseProcMountsRoot(strings.NewReader(content))
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

func TestParseProcMountsRoot_SkipsMalformedLines(t *testing.T) {
	content := `tooshort
/dev/sda1 / ext4 rw,relatime 0 0
`
	devicePath, fsType, err := parseProcMountsRoot(strings.NewReader(content))
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

func TestParseProcMountsRoot_ReturnsFirstRootMount(t *testing.T) {
	// If multiple root entries exist, return the first
	content := `/dev/sda1 / ext4 rw 0 0
/dev/sda2 / btrfs rw 0 0
`
	devicePath, _, err := parseProcMountsRoot(strings.NewReader(content))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if devicePath != "/dev/sda1" {
		t.Errorf("expected first root '/dev/sda1', got %q", devicePath)
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

func TestParseProcMountsRoot_Empty(t *testing.T) {
	devicePath, fsType, err := parseProcMountsRoot(strings.NewReader(""))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if devicePath != "" || fsType != "" {
		t.Errorf("expected empty results for empty input, got %q %q", devicePath, fsType)
	}
}
