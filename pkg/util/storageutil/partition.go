package storageutil

import (
	"fmt"
	"os/exec"
	"strings"

	"golang.org/x/sys/unix"
)

type Partition interface {
	MountCommand(mountTargetPath string) *exec.Cmd
	MountPath() (string, error)
	Path() string
	SizeBytes() (int, error)
	Stat() (*unix.Statfs_t, error)
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
