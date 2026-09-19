package storageutil

import (
	"os/exec"
	"strings"
	"testing"

	"golang.org/x/sys/unix"
)

// failingPartition is a partition whose mount command prints to stderr and
// fails, the way mount does on a bad filesystem.
type failingPartition struct{}

func (failingPartition) MountCommand(string) *exec.Cmd {
	return exec.Command("sh", "-c", "echo 'mount: wrong fs type, boom' >&2; exit 32")
}
func (failingPartition) MountPath() (string, error)    { return "", nil }
func (failingPartition) Path() string                  { return "/dev/fake1" }
func (failingPartition) SizeBytes() (int, error)       { return 0, nil }
func (failingPartition) Stat() (*unix.Statfs_t, error) { return nil, nil }

// unmountedDevice is a storage device with one failingPartition.
type unmountedDevice struct{}

func (unmountedDevice) GetPath() string                 { return "/sys/bus/usb/devices/fake" }
func (unmountedDevice) GetVendorID() string             { return "0781" }
func (unmountedDevice) GetProductID() string            { return "55dd" }
func (unmountedDevice) GetManufacturer() string         { return "Fake" }
func (unmountedDevice) GetProduct() string              { return "Drive" }
func (unmountedDevice) GetSerial() string               { return "fake-serial" }
func (unmountedDevice) GetMountPath() string            { return "" }
func (unmountedDevice) BlockDevicePath() (string, bool) { return "/dev/fake", true }
func (unmountedDevice) IsStorageDevice() bool           { return true }
func (unmountedDevice) Partitions() ([]Partition, error) {
	return []Partition{failingPartition{}}, nil
}

// A failed mount has to say why. "exit status 1" alone could not tell sudo
// refusing apart from mount failing (#2115).
func TestAutoMountDevice_FailureCarriesMountOutput(t *testing.T) {
	t.Setenv("HOME", t.TempDir())

	_, err := AutoMountDevice(unmountedDevice{})
	if err == nil {
		t.Fatal("AutoMountDevice succeeded with a failing mount command")
	}
	for _, want := range []string{"mount command failed", "exit status 32", "wrong fs type, boom"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not contain %q", err, want)
		}
	}
}

func TestRunMountCommand(t *testing.T) {
	if err := RunMountCommand(exec.Command("sh", "-c", "echo fine")); err != nil {
		t.Errorf("a succeeding command returned %v", err)
	}
	if err := RunMountCommand(exec.Command("sh", "-c", "exit 1")); err == nil || err.Error() != "exit status 1" {
		t.Errorf("a silent failure = %v, want the bare exit status", err)
	}
}
