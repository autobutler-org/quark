// Package indexutil keeps the file index behind filename search: one row per
// file and folder on every managed device, with each file's name, size and
// mtime, in the database's file_index table (044_file_index). It is brought in
// line with each device's files namespace in the VFS registry at startup and
// kept current from file events. It also answers a folder's total size
// without a walk. The trash and the other internal names are never indexed.
package indexutil

import (
	"context"
	"sync/atomic"
	"time"

	"github.com/autobutler-org/quark/internal/db"
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
	// Size is the file's size in bytes when it was last indexed.
	Size int64
	// ModTime is the file's modification time when it was last indexed.
	ModTime time.Time
}

// FileIndex is the file index of every managed device, keyed by device
// serial, held in the database rather than in process memory (#2956), so every
// process on one database answers from the same index and a restart starts
// from what the last one left.
//
// A path is stored as the folder it sits in and its name, and folders have
// rows of their own, so an event naming a folder reaches everything under it
// in one statement: a delete drops the range of rows under it and a move
// rewrites their folder (#2754).
type FileIndex struct {
	database *db.DatabaseSqlc
	// lastStamp is the last indexed_at handed out, so two writes in one
	// nanosecond still stamp in order.
	lastStamp atomic.Int64
}

// NewFileIndex returns the file index held in database.
func NewFileIndex(database *db.DatabaseSqlc) *FileIndex {
	return &FileIndex{database: database}
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
