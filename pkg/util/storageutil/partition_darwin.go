package storageutil

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"golang.org/x/sys/unix"
	"howett.net/plist"
)

type partition struct {
	path string
}

// FsType is always "": macOS mounts an external drive itself, so Quark is
// never asked to pick one of its partitions to mount.
func (p *partition) FsType() string {
	return ""
}

func (p *partition) MountCommand(mountTargetPath string) *exec.Cmd {
	return exec.Command("mount", p.path, mountTargetPath)
}

func UnmountCommand(mountTargetPath string) *exec.Cmd {
	return exec.Command("umount", mountTargetPath)
}

func (p *partition) MountPath() (string, error) {
	// Check /proc/mounts for this device
	data, err := os.ReadFile("/proc/mounts")
	if err != nil {
		return "", fmt.Errorf("failed to read /proc/mounts: %w", err)
	}
	lines := strings.SplitSeq(string(data), "\n")
	for line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		if fields[0] == p.path {
			return fields[1], nil
		}
	}
	return "", fmt.Errorf("partition %s is not mountable", p.path)
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

	out, err := exec.Command("diskutil", "info", "-plist", p.path).Output()
	if err != nil {
		return 0, err
	}
	var info struct {
		TotalSize int64 `plist:"TotalSize"`
	}
	if _, err := plist.Unmarshal(out, &info); err != nil {
		return 0, err
	}
	return int(info.TotalSize), nil
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
