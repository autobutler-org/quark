package storageutil

import (
	"errors"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"syscall"
)

// IsNotExist reports whether err says a path does not exist. Unlike
// os.IsNotExist it also counts a path that runs through a regular file
// ("notes.txt/pic.jpg"), which the OS reports as ENOTDIR rather than ENOENT.
func IsNotExist(err error) bool {
	return errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ENOTDIR)
}

func getServiceDataDir() string {
	return "/var/lib/quark/data"
}

func isRunningAsServiceUser() bool {
	u, err := user.Current()
	if err != nil {
		return false
	}
	return u.Username == "quark"
}

// ConstructFilesDir returns the on-disk storage root for a data directory.
func ConstructFilesDir(dataDir string) string {
	return filepath.Join(dataDir, "files")
}

func GetFilesDir() (string, error) {
	filesPath := ConstructFilesDir(GetDataDir())
	if err := os.MkdirAll(filesPath, 0755); err != nil {
		return "", fmt.Errorf("failed to create files directory: %w", err)
	}
	return filesPath, nil
}

// GetFilesDirForDevice returns the storage root on an external device.
func GetFilesDirForDevice(mountPoint string) (string, error) {
	if mountPoint == "" {
		return "", errors.New("mount point is empty")
	}

	mountInfo, err := os.Stat(mountPoint)
	if err != nil {
		return "", err
	}
	if !mountInfo.IsDir() {
		return "", errors.New("mount point is not a directory")
	}

	dataDir := GetDataDirForDevice(mountPoint)
	filesPath := ConstructFilesDir(dataDir)
	if err := os.MkdirAll(filesPath, 0755); err != nil {
		return "", fmt.Errorf("failed to create files directory for device at %s: %v", mountPoint, err)
	}
	return filesPath, nil
}

// GetDataDirForDevice returns the data directory path for a specific device mount point
func GetDataDirForDevice(mountPoint string) string {
	// For the main system device (root filesystem or /System/Volumes/Data on macOS),
	// use the standard user-specific data directory location
	isSystemDevice := mountPoint == "/" || mountPoint == "/System/Volumes/Data"

	if isSystemDevice {
		// Use platform-specific user directories (~/Library/Application Support/Quark/data on macOS)
		switch runtime.GOOS {
		case "darwin": // coverage: ignore - Not run in CI
			homeDir, err := os.UserHomeDir()
			if err != nil {
				homeDir = "/" // coverage: ignore - requires UserHomeDir to fail
			}
			return filepath.Join(homeDir, "Library", "Application Support", "Quark", "data")
		case "linux": // coverage: ignore - Not run in mac dev environments
			if isRunningAsServiceUser() {
				return getServiceDataDir() // coverage: ignore
			}
			homeDir, err := os.UserHomeDir()
			if err != nil {
				homeDir = "/var/lib" // coverage: ignore
			}
			return filepath.Join(homeDir, "quark", "data") // coverage: ignore
		}
	}

	// For external devices, use quark directory on the device itself
	return filepath.Join(mountPoint, "quark", "data")
}

func GetDataDir() string {
	// Get data directory for the system device
	switch runtime.GOOS {
	case "darwin": // coverage: ignore - Not run in CI
		// On macOS, the system mount point can be / or /System/Volumes/Data
		// Use / as the canonical reference
		return GetDataDirForDevice("/")
	case "linux": // coverage: ignore - Not run in mac dev environments
		return GetDataDirForDevice("/")
	default:
		panic(fmt.Sprintf("unsupported OS: %s", runtime.GOOS)) // coverage: ignore - panic on unsupported OS
	}
}

func GetMountsDir() (string, error) {
	mountDir := filepath.Join(GetDataDir(), "mounts")
	if err := os.MkdirAll(mountDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create mounts directory: %w", err)
	}
	return mountDir, nil
}
