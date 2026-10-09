package vfs

import (
	"context"
	"errors"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// Walk streams the subtree at path on this namespace's device, one entry at a
// time, so a walk of the whole library never materializes it. Directories
// carry their own size, not their contents', which spares the subtree walk
// per folder a single-level List pays. See [Walk].
func (v *StorageServiceVFS) Walk(ctx context.Context, path string, visit WalkFunc) error {
	dir, err := v.resolve(path)
	if err != nil {
		return err
	}
	device, err := v.svc.FindManagedDeviceBySerial(v.serial)
	if err != nil {
		return err
	}
	var name, dataDir string
	if device != nil {
		name, dataDir = device.Name, device.DataDir
	}
	err = hostWalkDir(ctx, dir, name, dataDir, v.serial, func(f walkedFile) error {
		return visit(deviceFileInfoToVFS(f.Info, v.namespaceID, path, f.RelPath))
	})
	if errors.Is(err, storageutil.ErrPathNotFound) {
		return ErrNotFound
	}
	return err
}
