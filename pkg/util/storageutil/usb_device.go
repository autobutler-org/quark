package storageutil

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
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

// Partitions returns all partitions for this USB device (e.g., /dev/sda1, /dev/sda2, ...).
// If no sub-partitions exist (whole-disk filesystem), the block device itself is returned
// as a single partition entry so that mount detection still works.
func (u *usbDevice) Partitions() ([]Partition, error) {
	blockDev, exists := u.BlockDevicePath()
	if !exists {
		return nil, errors.New("block device not found")
	}
	pattern := blockDev + "*"
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, err
	}
	var partitions []Partition
	for _, m := range matches {
		if m != blockDev {
			partitions = append(partitions, &partition{path: m})
		}
	}
	// If no sub-partitions found, the drive may use a whole-disk filesystem
	// (e.g., mkfs.ext4 /dev/sda without a partition table). Include the block
	// device itself so checkIfMounted can find it in /proc/mounts.
	if len(partitions) == 0 {
		partitions = append(partitions, &partition{path: blockDev})
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
