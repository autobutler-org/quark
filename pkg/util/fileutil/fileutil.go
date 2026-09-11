// Package fileutil holds the services behind /api/v0/files: the listings the
// file browser pages through, the archive views that read only headers, the
// download pipeline that zips a folder or re-encodes an image on its way out,
// and the mutations (delete, move, new folder) the browser sends back.
//
// Every entry point takes the two sources these endpoints have always had —
// the VFS namespace when one is registered, the StorageService walking managed
// devices otherwise — and makes that choice here rather than in a handler.
//
// HTTP concerns stay with the caller: [NotFoundError] and [ErrNoFilesNamespace]
// are what a status code is derived from, and the response headers, the IO
// semaphore and its 503 belong to the handler.
package fileutil

import (
	"errors"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// filesNamespace is the VFS namespace holding the local file store. Registered
// by deputil.DefaultDependencies; absent in older deployments and in tests that
// exercise the StorageService directly.
const filesNamespace = "files"

// DefaultDeviceSerial is the serial the internal (non-USB) device is reported
// under: it has no USB descriptor to take one from.
const DefaultDeviceSerial = ""

// FileNode is a file or folder as the listing endpoints report it.
type FileNode struct {
	Name           string `json:"name"`
	Size           int64  `json:"size"`
	CompressedSize int64  `json:"compressedSize,omitempty"`
	IsDir          bool   `json:"isDir"`
	DeviceName     string `json:"deviceName"`
	DevicePath     string `json:"devicePath"`
	DirPath        string `json:"dirPath"` // Directory path containing the file, for easier client-side handling
	FullPath       string `json:"fullPath"`
	DeviceSerial   string `json:"deviceSerial"`
	FileType       string `json:"fileType"` // Kept for older clients; route viewers by file name instead
}

// FileNodeWithTime is a FileNode carrying its modification time, for the
// listings that sort newest-first.
type FileNodeWithTime struct {
	FileNode
	ModifiedAt time.Time `json:"modifiedAt"`
}

// ErrNoFilesNamespace reports a VFS registry without the local files namespace.
// Nothing can be listed or written through a registry that does not have it.
var ErrNoFilesNamespace = errors.New("files namespace not registered")

// NotFoundError reports a path none of the sources could produce. The handler
// answers it with 404; the message reaches the client unchanged.
type NotFoundError struct {
	Err error
}

func (e *NotFoundError) Error() string { return e.Err.Error() }

func (e *NotFoundError) Unwrap() error { return e.Err }

// UnsupportedError reports something the request asked for that this build
// cannot do — an archive compressed with a method Go's archive/zip does not
// implement, say. The caller is at fault, not the server, so the handler
// answers it with 400 rather than the bare 500 it used to (#1705).
type UnsupportedError struct {
	Err error
}

func (e *UnsupportedError) Error() string { return e.Err.Error() }

func (e *UnsupportedError) Unwrap() error { return e.Err }

// FilesVFS returns the VFS backing the local files namespace, or nil when
// there is none to route to and the StorageService has to serve the request.
func FilesVFS(registry vfs.Registry) vfs.VFS {
	if registry == nil {
		return nil
	}
	fsys, ok := registry.Get(filesNamespace)
	if !ok {
		return nil
	}
	return fsys
}

// DeviceSerial reports the serial a managed device is addressed by. The
// internal device has no USB descriptor, so it answers to the empty serial.
func DeviceSerial(device storageutil.ManagedDevice) string {
	if device.UsbInfo != nil {
		return device.UsbInfo.GetSerial()
	}
	return DefaultDeviceSerial
}

// SelectDevices narrows the managed devices to the requested serials. No
// serials at all means every device, which is what an unscoped listing wants.
func SelectDevices(devices []storageutil.ManagedDevice, serials []string) []storageutil.ManagedDevice {
	if len(serials) == 0 {
		return devices
	}
	// Build a set for quick lookup
	serialSet := make(map[string]bool, len(serials))
	for _, s := range serials {
		serialSet[s] = true
	}
	var selected []storageutil.ManagedDevice
	for _, d := range devices {
		if serialSet[DeviceSerial(d)] {
			selected = append(selected, d)
		}
	}
	return selected
}
