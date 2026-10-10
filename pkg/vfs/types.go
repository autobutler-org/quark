package vfs

import "bytes"

// bytesFile is the [File] MemVFS and DBVFS hand out over content they already
// hold in memory, bounded by [MaxInMemoryWriteBytes]. Closing it releases
// nothing.
type bytesFile struct {
	*bytes.Reader
}

// Close implements io.Closer.
func (bytesFile) Close() error { return nil }
