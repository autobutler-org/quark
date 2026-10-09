package vfs

import (
	"bytes"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// bytesFile is the [File] MemVFS and DBVFS hand out over content they already
// hold in memory, bounded by [MaxInMemoryWriteBytes]. Closing it releases
// nothing.
type bytesFile struct {
	*bytes.Reader
}

// Close implements io.Closer.
func (bytesFile) Close() error { return nil }

// walkedFile is one entry produced by hostWalkDir: the entry itself plus
// its path relative to the directory the walk started from.
type walkedFile struct {
	Info *storageutil.DeviceFileInfo
	// RelPath is slash-separated and relative to the walk root, e.g.
	// "sub/deep.qdoc". hostListDir's single-level listing only ever needs
	// a base name, which is why callers that walk need this instead.
	RelPath string
}

// resolvedTrashRef is a TrashRef checked against the disk.
type resolvedTrashRef struct {
	// itemPath is the trashed item on disk.
	itemPath string
	// target is what the reference names: itemPath, or a path inside it.
	target string
	// rel is the reference's path, cleaned and slash-separated; empty for
	// the item itself.
	rel string
}
