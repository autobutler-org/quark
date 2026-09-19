package deviceutil

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// EnableParams mounts the first partition of a USB storage device under the
// mounts directory and prepares the Quark data directory on it.
type EnableParams struct {
	// Storage finds the device and holds the status cache to invalidate.
	Storage *storageutil.StorageService
	// Serial identifies the USB device to mount.
	Serial string
}

// EnableResult reports where the device ended up.
type EnableResult struct {
	MountPath string
	FilesDir  string
}

// Enable mounts a USB storage device.
func Enable(params EnableParams) (EnableResult, error) {
	targetDevice, err := params.Storage.FindUsbDeviceBySerial(params.Serial)
	if err != nil {
		return EnableResult{}, &NotFoundError{Err: fmt.Errorf("USB device not found: %w", err)}
	}

	if !targetDevice.IsStorageDevice() {
		return EnableResult{}, invalid(errors.New("specified USB device is not a storage device"))
	}

	if mountPath := targetDevice.GetMountPath(); mountPath != "" {
		return EnableResult{}, invalid(errors.New("USB storage device is already mounted"))
	}

	partitions, err := targetDevice.Partitions()
	if err != nil {
		return EnableResult{}, fmt.Errorf("failed to retrieve partitions: %w", err)
	}
	if len(partitions) == 0 {
		return EnableResult{}, errors.New("no partitions found on USB storage device")
	}

	partition := partitions[0]
	mountPath, _ := partition.MountPath()
	if mountPath != "" {
		return EnableResult{}, invalid(errors.New("partition is already mounted"))
	}

	mountTargetDir, err := storageutil.GetMountsDir()
	if err != nil {
		return EnableResult{}, fmt.Errorf("failed to get mounts directory: %w", err)
	}
	mountTargetPath := filepath.Join(mountTargetDir, targetDevice.GetSerial())
	if err := os.MkdirAll(mountTargetPath, os.ModeDir|os.ModePerm); err != nil {
		return EnableResult{}, fmt.Errorf("failed to create mount target directory: %w", err)
	}
	if err := storageutil.RunMountCommand(partition.MountCommand(mountTargetPath)); err != nil {
		return EnableResult{}, fmt.Errorf("failed to execute mount command: %w", err)
	}

	// Invalidate the device status cache so the next poll reflects the new
	// mount state immediately rather than returning stale data for up to 10s.
	params.Storage.InvalidateDeviceCache()

	filesDir, err := storageutil.GetFilesDirForDevice(mountTargetPath)
	if err != nil {
		return EnableResult{}, fmt.Errorf("failed to initialize data directory on mounted device: %w", err)
	}

	return EnableResult{MountPath: mountTargetPath, FilesDir: filesDir}, nil
}

// DisableParams unmounts a USB storage device.
type DisableParams struct {
	// Storage finds the device and holds the status cache to invalidate.
	Storage *storageutil.StorageService
	// Serial identifies the USB device to unmount.
	Serial string
}

// DisableResult reports a completed unmount.
type DisableResult struct{}

// Disable unmounts a USB storage device.
func Disable(params DisableParams) (DisableResult, error) {
	targetDevice, err := params.Storage.FindUsbDeviceBySerial(params.Serial)
	if err != nil {
		return DisableResult{}, &NotFoundError{Err: fmt.Errorf("USB device not found: %w", err)}
	}

	if !targetDevice.IsStorageDevice() {
		return DisableResult{}, invalid(errors.New("specified USB device is not a storage device"))
	}

	mountPath := targetDevice.GetMountPath()
	if mountPath == "" {
		return DisableResult{}, invalid(errors.New("USB storage device is not mounted"))
	}

	if err := storageutil.RunMountCommand(storageutil.UnmountCommand(mountPath)); err != nil {
		return DisableResult{}, fmt.Errorf("failed to execute unmount command: %w", err)
	}

	// Invalidate the device status cache so the UI reflects the unmount immediately.
	params.Storage.InvalidateDeviceCache()

	return DisableResult{}, nil
}
