// Package indexutil keeps the in-memory filename index behind filename
// search: one tree of folders per managed device, built by walking each
// device's files namespace in the VFS registry and kept current from file
// events. The trash and the other internal names are never indexed.
package indexutil

import (
	"context"
	"sync"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// IndexedFile is one file the index holds.
type IndexedFile struct {
	// Name is the file name, with no directory.
	Name string
	// RelPath is the path within the device's files namespace, e.g.
	// "docs/notes.txt".
	RelPath string
	// DeviceSerial names the device, empty for the internal drive. The file
	// lives in the namespace vfs.FilesNamespace(DeviceSerial).
	DeviceSerial string
}

// FileIndex is a thread-safe in-memory index of the files on every managed
// device, keyed by device serial. It is built once at startup and kept
// current from file events.
//
// Each device is a tree of folders, so an event naming a folder reaches
// everything under it in one step: a delete unlinks the folder's node and a
// move reattaches it, whatever it holds (#2754). Paths are never stored; a
// search rebuilds them on the way down, and only for the files it returns.
//
// A folder keeps the names of its files sorted and end to end in one string,
// so a file costs its name's bytes and a 4-byte offset (#2760): ~30 B a file
// against ~100 B for a map per folder (BenchmarkFileIndexHeap).
type FileIndex struct {
	mu    sync.RWMutex
	roots map[string]*indexDir // key: device serial, "" for the internal drive
}

// NewFileIndex creates and returns an empty FileIndex.
func NewFileIndex() *FileIndex {
	return &FileIndex{roots: make(map[string]*indexDir)}
}

// BuildAndWatchParams wires a FileIndex to the server.
type BuildAndWatchParams struct {
	// Ctx bounds the walks; nil is context.Background.
	Ctx context.Context
	// Bus carries the file events that keep the index current.
	Bus *eventbus.Bus
	// Registry holds one files namespace per managed device.
	Registry vfs.Registry
	// Storage, when set, signals that the device set changed, so a device
	// plugged in after startup is indexed once its namespace is registered,
	// and one unplugged is dropped.
	Storage *storageutil.StorageService
}
