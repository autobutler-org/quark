package vfs

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// readBounded reads r whole, refusing more than [MaxInMemoryWriteBytes]. It
// reads one byte past the cap so an oversized write is rejected rather than
// silently truncated into a half-stored file.
func readBounded(r io.Reader) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, MaxInMemoryWriteBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > MaxInMemoryWriteBytes {
		return nil, ErrTooLarge
	}
	return data, nil
}

// moveFileIn is the body of every [FileMover]. With IfNoneMatch set it
// hard-links and then unlinks the source, because os.Link refuses an existing
// destination atomically where os.Rename would replace it. When the fast path
// cannot work — the source is on another filesystem (EXDEV), or this one has
// no hard links (exFAT) — it falls back to write, the copy the caller would
// have made anyway.
func moveFileIn(srcAbs string, dstAbs string, opts WriteOptions, write func(io.Reader) error) error {
	if err := os.MkdirAll(filepath.Dir(dstAbs), 0o755); err != nil {
		return err
	}
	// Staged by os.CreateTemp, so 0600; match what WriteFileAtomic leaves.
	if err := os.Chmod(srcAbs, 0o644); err != nil {
		return err
	}
	// The name has to reach the disk after the bytes it names, or a power cut
	// leaves an empty file where the caller was told a whole one landed (#2517).
	if err := storageutil.SyncFile(srcAbs); err != nil {
		return err
	}
	if opts.IfNoneMatch == "*" {
		err := os.Link(srcAbs, dstAbs)
		if err == nil {
			// The file is in place. A source name left behind is clutter the
			// caller cleans up, not a reason to report a failed move.
			_ = os.Remove(srcAbs)
			return storageutil.SyncDir(filepath.Dir(dstAbs))
		}
		if errors.Is(err, fs.ErrExist) {
			return ErrConflict
		}
	} else if err := os.Rename(srcAbs, dstAbs); err == nil {
		return storageutil.SyncDir(filepath.Dir(dstAbs))
	}

	src, err := os.Open(srcAbs)
	if err != nil {
		return err
	}
	defer func() { _ = src.Close() }()
	if err := write(src); err != nil {
		return err
	}
	_ = os.Remove(srcAbs)
	return nil
}
