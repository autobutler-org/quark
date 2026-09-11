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

// writeAtomic streams r into a temp file beside absPath and renames it over
// absPath, so the real name never holds a half-written file and a failed write
// leaves nothing behind. Listings skip the temp by its prefix (#1828).
func writeAtomic(absPath string, r io.Reader) error {
	dir := filepath.Dir(absPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, storageutil.WriteTempPrefix+"*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	// A no-op once the rename has happened; cleans up after any failure before it.
	defer func() { _ = os.Remove(tmpName) }()

	if _, err := io.Copy(tmp, r); err != nil {
		_ = tmp.Close()
		return err
	}
	// os.CreateTemp makes 0600; a renamed-in file gets what os.Create would
	// have given it under the usual 022 umask.
	if err := tmp.Chmod(0o644); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, absPath)
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
	// Staged by os.CreateTemp, so 0600; match what writeAtomic leaves.
	if err := os.Chmod(srcAbs, 0o644); err != nil {
		return err
	}
	if opts.IfNoneMatch == "*" {
		err := os.Link(srcAbs, dstAbs)
		if err == nil {
			// The file is in place. A source name left behind is clutter the
			// caller cleans up, not a reason to report a failed move.
			_ = os.Remove(srcAbs)
			return nil
		}
		if errors.Is(err, fs.ErrExist) {
			return ErrConflict
		}
	} else if err := os.Rename(srcAbs, dstAbs); err == nil {
		return nil
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
