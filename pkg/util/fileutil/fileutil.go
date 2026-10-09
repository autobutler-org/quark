// Package fileutil holds the services behind /api/v0/files: the listings the
// file browser pages through, the archive views that read only headers, the
// download pipeline that zips a folder or re-encodes an image on its way out,
// and the mutations (delete, move, new folder) the browser sends back.
//
// Every entry point reads and writes through the VFS registry, which holds one
// namespace per managed device (#2639): a request's serial picks the namespace
// with [FilesVFS], and an unscoped listing fans out over all of them (#2642).
//
// HTTP concerns stay with the caller: [NotFoundError] and [ErrNoFilesNamespace]
// are what a status code is derived from, and the response headers, the IO
// semaphore and its 503 belong to the handler.
package fileutil

import (
	"errors"
	"time"

	"github.com/autobutler-org/quark/pkg/vfs"
)

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
	// ModifiedAt is when the entry last changed. It is left out when the source
	// does not say, as some entries inside an archive do not.
	ModifiedAt time.Time `json:"modifiedAt,omitzero"`
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

// InvalidRequestError reports a request that can never succeed as written —
// a path that climbs out of the files directory, say, or a batch over its
// limit. The caller is at fault, so the handler answers it with 400 (#2573).
type InvalidRequestError struct {
	Err error
}

func (e *InvalidRequestError) Error() string { return e.Err.Error() }

func (e *InvalidRequestError) Unwrap() error { return e.Err }

// ErrNoDevice reports a serial with no files namespace: a storage device that
// is not attached. The handler answers it with 404.
var ErrNoDevice = errors.New("storage device not found")

// FilesVFS returns the namespace holding the files of the device with this
// serial, the internal drive's for the empty serial. A registry without the
// internal drive's namespace is [ErrNoFilesNamespace]; a serial with no
// namespace of its own is a [NotFoundError] wrapping [ErrNoDevice], never the
// internal drive.
func FilesVFS(registry vfs.Registry, serial string) (vfs.VFS, error) {
	if registry == nil {
		return nil, ErrNoFilesNamespace
	}
	fsys, ok := registry.Get(vfs.FilesNamespace(serial))
	switch {
	case ok:
		return fsys, nil
	case serial == "":
		return nil, ErrNoFilesNamespace
	}
	if _, ok := registry.Get(vfs.FilesNamespace("")); !ok {
		return nil, ErrNoFilesNamespace
	}
	return nil, notFound(ErrNoDevice)
}
