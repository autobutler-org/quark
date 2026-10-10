package vfs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"syscall"

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

// copyFile is the body of every [VFS.Copy] and of [CopyBetween]: it streams
// the source into dst's Write, the atomic write path, so a reader of dst sees
// either nothing or the whole copy.
func copyFile(ctx context.Context, src VFS, srcPath string, dst VFS, dstPath string, opts CopyOptions) error {
	info, err := src.Stat(ctx, srcPath)
	if err != nil {
		return err
	}
	if info.IsDir {
		return ErrIsDirectory
	}
	f, err := src.Open(ctx, srcPath)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	return dst.Write(ctx, dstPath, f, WriteOptions{ContentType: info.MimeType, IfNoneMatch: opts.IfNoneMatch})
}

// hostErr maps an error from the host filesystem onto the VFS contract, which
// every host-backed namespace shares (#2640): only a path that does not exist
// is [ErrNotFound], and a permission failure is [ErrPermissionDenied] rather
// than reading as a missing file. Anything else passes through.
func hostErr(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, fs.ErrNotExist), errors.Is(err, syscall.ENOTDIR):
		return ErrNotFound
	case errors.Is(err, fs.ErrPermission):
		return fmt.Errorf("%w: %w", ErrPermissionDenied, err)
	}
	return err
}

// hostOpen opens the host file at absPath for [VFS.Open]. A directory is
// [ErrIsDirectory].
func hostOpen(absPath string) (File, error) {
	f, err := os.Open(absPath)
	if err != nil {
		return nil, hostErr(err)
	}
	fi, err := f.Stat()
	if err != nil {
		_ = f.Close()
		return nil, hostErr(err)
	}
	if fi.IsDir() {
		_ = f.Close()
		return nil, ErrIsDirectory
	}
	return f, nil
}

// hostWrite streams r to the host file at absPath for [VFS.Write]. With
// IfNoneMatch "*" a taken name is [ErrConflict]. A name already taken is
// refused before r is read, so a caller can retry another name with the same
// reader; the refusal that counts happens in the same step that commits the
// file, so two writers racing for one name cannot both win.
func hostWrite(absPath string, r io.Reader, opts WriteOptions) error {
	if opts.IfNoneMatch != "*" {
		return hostErr(storageutil.WriteFileAtomic(absPath, r))
	}
	if _, err := os.Lstat(absPath); err == nil {
		return ErrConflict
	}
	err := storageutil.WriteFileAtomicExclusive(absPath, r)
	if errors.Is(err, fs.ErrExist) {
		return ErrConflict
	}
	return hostErr(err)
}

// hostDelete removes the host file or directory at absPath for [VFS.Delete].
// A directory with entries is [ErrNotEmpty] unless opts.Recursive is set.
func hostDelete(absPath string, opts DeleteOptions) error {
	fi, err := os.Lstat(absPath)
	if err != nil {
		return hostErr(err)
	}
	if fi.IsDir() && opts.Recursive {
		return hostErr(os.RemoveAll(absPath))
	}
	err = os.Remove(absPath)
	if errors.Is(err, syscall.ENOTEMPTY) || errors.Is(err, syscall.EEXIST) {
		return ErrNotEmpty
	}
	return hostErr(err)
}
