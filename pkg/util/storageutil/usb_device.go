package storageutil

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

type UsbDevice interface {
	// Member variable access
	GetPath() string
	GetVendorID() string
	GetProductID() string
	GetManufacturer() string
	GetProduct() string
	GetSerial() string
	GetMountPath() string
	// Functions
	BlockDevicePath() (string, bool)
	IsStorageDevice() bool
	Partitions() ([]Partition, error)
}

type usbDevice struct {
	Path         string `json:"path"`
	VendorID     string `json:"vendorID"`
	ProductID    string `json:"productID"`
	Manufacturer string `json:"manufacturer"`
	Product      string `json:"product"`
	Serial       string `json:"serial"`
	MountPath    string `json:"mountPath"`
}

func (u *usbDevice) GetPath() string {
	return u.Path
}

func (u *usbDevice) GetVendorID() string {
	return u.VendorID
}

func (u *usbDevice) GetProductID() string {
	return u.ProductID
}

func (u *usbDevice) GetManufacturer() string {
	return u.Manufacturer
}

func (u *usbDevice) GetProduct() string {
	return u.Product
}

func (u *usbDevice) GetSerial() string {
	return u.Serial
}

func (u *usbDevice) GetMountPath() string {
	return u.MountPath
}

func (u *usbDevice) UpdateStatus() error {
	mountPath, err := u.checkIfMounted()
	if err != nil {
		u.MountPath = ""
		return err
	}
	u.MountPath = mountPath
	return nil
}

func (u *usbDevice) BlockDevicePath() (string, bool) {
	usbDirName := filepath.Base(u.Path)
	blockDevs, _ := filepath.Glob("/sys/block/*/device")
	for _, dev := range blockDevs {
		resolved, err := filepath.EvalSymlinks(dev)
		if err != nil {
			continue
		}
		if ownsBlockDevice(usbDirName, resolved) {
			blockDevName := filepath.Base(filepath.Dir(dev))
			return filepath.Join("/dev", blockDevName), true
		}
	}
	return "", false
}

// ownsBlockDevice reports whether the resolved sysfs path of a block device
// sits under one of usbDirName's own interfaces ("2-1.1:1.0" for "2-1.1").
// Matching the bare device name instead would also claim every hub upstream
// of the disk: a drive behind an adapter resolves through ".../2-1/2-1.1/...",
// and the hub "2-1" would be listed as a storage device.
func ownsBlockDevice(usbDirName, resolved string) bool {
	for part := range strings.SplitSeq(resolved, string(os.PathSeparator)) {
		if strings.HasPrefix(part, usbDirName+":") {
			return true
		}
	}
	return false
}

func (u *usbDevice) IsStorageDevice() bool {
	if strings.Contains(u.Product, "Host Controller") {
		return false
	}
	_, exists := u.BlockDevicePath()
	return exists
}

// Partitions returns the device's partitions in partition-number order, so
// /dev/sda10 follows /dev/sda2. If it has none (a whole-disk filesystem), the
// block device itself is returned as the one partition, so mount detection and
// mounting still work.
func (u *usbDevice) Partitions() ([]Partition, error) {
	blockDev, exists := u.BlockDevicePath()
	if !exists {
		return nil, errors.New("block device not found")
	}
	return sysfsPartitions("/sys/block", filepath.Base(blockDev))
}

// sysfsPartitions lists block device name's partitions from sysfs: each child
// directory of sysBlock/<name> holding a "partition" file, which carries its
// number. Reading sysfs rather than globbing /dev orders them by that number
// and does not depend on the /dev nodes.
func sysfsPartitions(sysBlock, name string) ([]Partition, error) {
	entries, err := os.ReadDir(filepath.Join(sysBlock, name))
	if err != nil {
		return nil, err
	}
	type numbered struct {
		number int
		name   string
	}
	var found []numbered
	for _, entry := range entries {
		data, err := os.ReadFile(filepath.Join(sysBlock, name, entry.Name(), "partition"))
		if err != nil {
			continue
		}
		number, err := strconv.Atoi(strings.TrimSpace(string(data)))
		if err != nil {
			continue
		}
		found = append(found, numbered{number: number, name: entry.Name()})
	}
	slices.SortFunc(found, func(a, b numbered) int { return cmp.Compare(a.number, b.number) })
	// No partitions: the drive may carry a whole-disk filesystem (mkfs.ext4
	// /dev/sda without a partition table), so offer the disk itself.
	if len(found) == 0 {
		return []Partition{&partition{path: filepath.Join("/dev", name)}}, nil
	}
	partitions := make([]Partition, 0, len(found))
	for _, f := range found {
		partitions = append(partitions, &partition{path: filepath.Join("/dev", f.name)})
	}
	return partitions, nil
}

func (u *usbDevice) checkIfMounted() (string, error) {
	partitions, err := u.Partitions()
	if err != nil {
		return "", err
	}
	for _, part := range partitions {
		mountPath, err := part.MountPath()
		if err == nil {
			return mountPath, nil
		}
	}
	return "", fmt.Errorf("no mounted partitions found for device %s", u.Path)
}
