package storageutil

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// AutoMountResult holds the outcome of a successful auto-mount operation.
type AutoMountResult struct {
	Serial          string
	MountTargetPath string
}

// AutoMountDevice mounts the first partition of the given USB storage device
// under the quark mounts directory, then initializes the files data
// directory structure on it.
//
// It is a no-op (returns nil, nil) if the device is already mounted.
// Returns an error if any step fails.
func AutoMountDevice(device UsbDevice) (*AutoMountResult, error) {
	if device.GetMountPath() != "" {
		return nil, nil // already mounted
	}

	serial := device.GetSerial()
	if serial == "" {
		return nil, errors.New("device has no serial number")
	}

	partitions, err := device.Partitions()
	if err != nil {
		return nil, fmt.Errorf("failed to list partitions: %w", err)
	}
	if len(partitions) == 0 {
		return nil, errors.New("no partitions found on device")
	}

	mountsDir, err := GetMountsDir()
	if err != nil {
		return nil, fmt.Errorf("failed to resolve mounts directory: %w", err)
	}

	mountTargetPath := filepath.Join(mountsDir, serial)
	if err := os.MkdirAll(mountTargetPath, os.ModeDir|os.ModePerm); err != nil {
		return nil, fmt.Errorf("failed to create mount target %s: %w", mountTargetPath, err)
	}

	if err := RunMountCommand(partitions[0].MountCommand(mountTargetPath)); err != nil {
		return nil, fmt.Errorf("mount command failed: %w", err)
	}

	if err := InitializeDeviceDataDir(mountTargetPath); err != nil {
		// Non-fatal: mount succeeded, data dir init failed. Log at call site.
		return &AutoMountResult{Serial: serial, MountTargetPath: mountTargetPath},
			fmt.Errorf("mounted but failed to initialize data dir: %w", err)
	}

	return &AutoMountResult{Serial: serial, MountTargetPath: mountTargetPath}, nil
}
