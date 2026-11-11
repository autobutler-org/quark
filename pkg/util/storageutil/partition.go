package storageutil

import (
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"golang.org/x/sys/unix"
)

type Partition interface {
	// FsType names the filesystem on the partition ("exfat", "ext4"), or ""
	// when it has none or it cannot be read.
	FsType() string
	MountCommand(mountTargetPath string) *exec.Cmd
	MountPath() (string, error)
	Path() string
	SizeBytes() (int, error)
	Stat() (*unix.Statfs_t, error)
}

// ErrNoFilesystem is [PickPartition]'s answer for a drive with no partition
// Quark can mount. The text is shown to the user as it is.
var ErrNoFilesystem = errors.New("this drive has no readable filesystem")

// PickPartition chooses the partition of a drive to mount: of those with a
// filesystem, the largest, and the first of equals. A drive formatted by
// Windows leads with a 16 MiB reserved partition that has none, so the first
// partition is not the one to mount (#4017).
func PickPartition(partitions []Partition) (Partition, error) {
	var picked Partition
	pickedSize := -1
	for _, p := range partitions {
		if p.FsType() == "" {
			continue
		}
		// A size that cannot be read counts as zero: the partition is still
		// mountable, it just loses to one whose size is known.
		size, _ := p.SizeBytes()
		if size > pickedSize {
			picked, pickedSize = p, size
		}
	}
	if picked == nil {
		return nil, ErrNoFilesystem
	}
	return picked, nil
}

// RunMountCommand runs a mount or umount command and, when it fails, puts
// what the command printed into the error. A bare "exit status 1" cannot tell
// sudo refusing apart from mount failing (#2115); the output can. It is a
// command's diagnostics, bounded by that command, not file content.
func RunMountCommand(cmd *exec.Cmd) error {
	out, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}
	if text := strings.TrimSpace(string(out)); text != "" {
		return fmt.Errorf("%w: %s", err, text)
	}
	return err
}
