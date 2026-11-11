//go:build linux

package storageutil

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"

	"golang.org/x/sys/unix"
)

type partition struct {
	path string
}

// nonUnixFilesystems is the set of filesystem types that don't support
// Unix ownership natively. These need uid/gid mount options so that the
// quark service user can write to the drive.
var nonUnixFilesystems = map[string]bool{
	"exfat":   true,
	"vfat":    true,
	"fat":     true,
	"fat32":   true,
	"ntfs":    true,
	"ntfs3":   true,
	"ntfs-3g": true,
	"msdos":   true,
}

// detectFsType names the filesystem on a block device, or "" when it has none
// or it cannot be read. udev's database comes first because anyone can read
// it, where blkid has to open the device and prints nothing for a service user
// outside the disk group (#4017). blkid covers a host without udev, such as
// the container image, which puts quark in the disk group.
func detectFsType(devicePath string) string {
	if fsType := udevFsType("/sys/class/block", "/run/udev/data", filepath.Base(devicePath)); fsType != "" {
		return fsType
	}
	out, err := exec.Command("blkid", "-o", "value", "-s", "TYPE", devicePath).Output()
	if err != nil {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(string(out)))
}

// udevFsType reads the filesystem type udev recorded for block device name:
// the ID_FS_TYPE line of udevData/b<major>:<minor>, the numbers coming from
// sysClassBlock/<name>/dev. It is "" when either file is missing.
func udevFsType(sysClassBlock, udevData, name string) string {
	dev, err := os.ReadFile(filepath.Join(sysClassBlock, name, "dev"))
	if err != nil {
		return ""
	}
	data, err := os.ReadFile(filepath.Join(udevData, "b"+strings.TrimSpace(string(dev))))
	if err != nil {
		return ""
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		if fsType, ok := strings.CutPrefix(line, "E:ID_FS_TYPE="); ok {
			return strings.ToLower(strings.TrimSpace(fsType))
		}
	}
	return ""
}

// mountServiceUID returns the uid and gid of the quark service user,
// falling back to the current process user if lookup fails.
func mountServiceUID() (uid, gid string) {
	if u, err := user.Lookup("quark"); err == nil {
		return u.Uid, u.Gid
	}
	if u, err := user.Current(); err == nil {
		return u.Uid, u.Gid
	}
	return "0", "0"
}

func (p *partition) FsType() string {
	return detectFsType(p.path)
}

func (p *partition) MountCommand(mountTargetPath string) *exec.Cmd {
	if nonUnixFilesystems[p.FsType()] {
		// Filesystems without native Unix permissions (exFAT, NTFS, FAT32)
		// need uid/gid mount options so the quark service user can write.
		uid, gid := mountServiceUID()
		return exec.Command(
			"sudo", "-n", "mount",
			"-o", fmt.Sprintf("uid=%s,gid=%s", uid, gid),
			p.path, mountTargetPath,
		)
	}
	return exec.Command("sudo", "-n", "mount", p.path, mountTargetPath)
}

func UnmountCommand(mountTargetPath string) *exec.Cmd {
	return exec.Command("sudo", "-n", "umount", mountTargetPath)
}

func (p *partition) MountPath() (string, error) {
	return findMountPath(p.path)
}

// findMountPath scans /proc/mounts for a device path, resolving symlinks
// on both sides so that /dev/disk/by-* entries match /dev/sdX paths.
func findMountPath(devicePath string) (string, error) {
	data, err := os.ReadFile("/proc/mounts")
	if err != nil {
		return "", fmt.Errorf("failed to read /proc/mounts: %w", err)
	}

	// Resolve the target device path to its real path for comparison.
	resolvedTarget, err := resolveDevicePath(devicePath)
	if err != nil {
		resolvedTarget = devicePath
	}

	lines := strings.SplitSeq(string(data), "\n")
	for line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		// Direct match first (fast path).
		if fields[0] == devicePath {
			return fields[1], nil
		}
		// Resolve symlinks in /proc/mounts entry and compare.
		resolvedMount, err := resolveDevicePath(fields[0])
		if err != nil {
			continue
		}
		if resolvedMount == resolvedTarget {
			return fields[1], nil
		}
	}
	return "", fmt.Errorf("device %s is not mounted", devicePath)
}

// resolveDevicePath resolves a /dev path through symlinks to its real path.
// This handles /dev/disk/by-uuid/*, /dev/disk/by-label/*, etc.
func resolveDevicePath(path string) (string, error) {
	if !strings.HasPrefix(path, "/dev/") {
		return path, nil
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		// Not a symlink or can't resolve — return as-is.
		return path, nil
	}
	return resolved, nil
}

func (p *partition) Path() string {
	return p.path
}

func (p *partition) SizeBytes() (int, error) {
	stat, err := p.Stat()
	if err == nil {
		// If we can stat, use that
		return int(stat.Blocks * uint64(stat.Bsize)), nil
	}

	// If not mounted, use ioctl on the block device
	f, err := os.Open(p.path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	size, err := unix.IoctlGetInt(int(f.Fd()), unix.BLKGETSIZE64)
	if err != nil {
		return 0, err
	}
	return size, nil
}

func (p *partition) Stat() (*unix.Statfs_t, error) {
	mountPath, err := p.MountPath()
	if err != nil {
		return nil, fmt.Errorf("partition %s is not mounted", p.path)
	}

	var stat unix.Statfs_t
	err = unix.Statfs(mountPath, &stat)
	if err != nil {
		return nil, fmt.Errorf("failed to statfs mount path %s: %w", mountPath, err)
	}
	return &stat, nil
}
