package fileversionutil

import (
	"context"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// lockStripes is how many mutexes the Store spreads files over. A file always
// maps to the same one, so work on one file is serialized while work on most
// others runs alongside it, with no lock map to grow or clean up.
const lockStripes = 64

// maxIndexBytes bounds what is read of an index. The store writes a few KiB at
// most; anything bigger was not written by it.
const maxIndexBytes = 1 << 20

// indexName is the index's file name inside a store.
const indexName = "index.json"

// snapExt ends every snapshot's file name. It is no document extension, so
// the content search never indexes a snapshot as a second copy of the file.
const snapExt = ".snap"

// idStampLayout is the UTC timestamp a version id starts with.
const idStampLayout = "20060102T150405Z"

// indexFile is index.json.
type indexFile struct {
	Versions []Version `json:"versions"`
}

// snapshotRequest is a snapshot, already validated, run under the file's lock.
type snapshotRequest struct {
	ctx      context.Context
	fsys     vfs.VFS
	path     string
	kind     Kind
	label    string
	authorID int64
	// force skips the auto rate limit, for the snapshot a restore takes.
	force bool
	// pinned is a version retention must keep this time: the one a restore
	// is about to read.
	pinned string
}

// countingWriter counts what passes through it.
type countingWriter struct {
	n int64
}

func (w *countingWriter) Write(p []byte) (int, error) {
	w.n += int64(len(p))
	return len(p), nil
}
