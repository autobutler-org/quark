package photoutil

import (
	"context"
	"fmt"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// DeviceFS is the namespace holding the files of the device with serial, the
// empty serial being the internal drive. A device with no namespace — one
// unplugged, or never attached — is [vfs.ErrNotFound], so its files read as
// missing rather than as the internal drive's (#2645).
func DeviceFS(registry vfs.Registry, serial string) (vfs.VFS, error) {
	if registry != nil {
		if fsys, ok := registry.Get(vfs.FilesNamespace(serial)); ok {
			return fsys, nil
		}
	}
	return nil, fmt.Errorf("%w: no namespace for device %q", vfs.ErrNotFound, serial)
}

// HostPath is the host path of relPath on fsys, for an external tool (dcraw,
// exiftool, ffmpeg) that can only take a path. A namespace not backed by a
// host directory has none, and is [vfs.ErrNotFound] for a file an external
// tool would need.
func HostPath(ctx context.Context, fsys vfs.VFS, relPath string) (string, error) {
	pather, ok := fsys.(vfs.HostPather)
	if !ok {
		return "", fmt.Errorf("%w: %s has no host path", vfs.ErrNotFound, relPath)
	}
	return pather.HostPath(ctx, relPath)
}
