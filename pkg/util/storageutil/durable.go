package storageutil

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"syscall"
)

// WriteFileAtomic streams r into a temp file beside absPath, flushes it to
// disk, and renames it over absPath, so the real name never holds a
// half-written file: not after a failed write, and not after a power cut.
// Without the flush, a rename can reach the disk before the bytes it names, and
// the file comes back empty under its real name (#2517). The temp carries
// [WriteTempPrefix] so listings skip it (#1828).
func WriteFileAtomic(absPath string, r io.Reader) error {
	// os.CreateTemp makes 0600; a renamed-in file gets what os.Create would
	// have given it under the usual 022 umask.
	return WriteFileAtomicPerm(absPath, r, 0o644)
}

// WriteFileAtomicPerm is [WriteFileAtomic] for a file that must carry perm,
// such as a private 0600 settings file. The temp never holds wider permissions
// than perm, so nothing secret is readable on the way in.
func WriteFileAtomicPerm(absPath string, r io.Reader, perm os.FileMode) error {
	return writeFileAtomic(absPath, r, perm, renameFile)
}

// WriteFileAtomicExclusive is [WriteFileAtomic] for a name that must not be
// taken: when absPath already exists it returns an error matching
// fs.ErrExist and leaves the existing file alone. The check and the commit are
// one step, so of two writers racing for one name exactly one wins — a stat
// before the rename let both through (#2640).
func WriteFileAtomicExclusive(absPath string, r io.Reader) error {
	return writeFileAtomic(absPath, r, 0o644, commitExclusive)
}

// writeFileAtomic is the body of [WriteFileAtomicPerm] and
// [WriteFileAtomicExclusive]: it streams r into a flushed temp beside absPath
// and hands the temp's name to commit to put in place.
func writeFileAtomic(absPath string, r io.Reader, perm os.FileMode, commit func(tmpName, absPath string) error) error {
	dir := filepath.Dir(absPath)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, WriteTempPrefix+"*")
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
	if err := tmp.Chmod(perm); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := syncFile(tmp); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := commit(tmpName, absPath); err != nil {
		return err
	}
	return SyncDir(dir)
}

// commitExclusive puts the finished temp at absPath only if absPath is free.
// os.Link refuses a taken name atomically where os.Rename would replace it. A
// filesystem without hard links (exFAT, common on USB drives) gets the same
// guarantee from O_EXCL: the name is reserved as an empty file and the temp
// renamed over the reservation, so the empty file exists only for the instant
// between the two calls.
func commitExclusive(tmpName, absPath string) error {
	err := linkFile(tmpName, absPath)
	if err == nil || errors.Is(err, fs.ErrExist) {
		// On success the temp's own name goes with writeFileAtomic's cleanup.
		return err
	}
	f, err := os.OpenFile(absPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(absPath)
		return err
	}
	if err := renameFile(tmpName, absPath); err != nil {
		_ = os.Remove(absPath)
		return err
	}
	return nil
}

// renameFile and syncFile are the steps a test swaps to stand in for a crash
// partway through [WriteFileAtomicPerm]; linkFile, for a filesystem without
// hard links under [WriteFileAtomicExclusive].
var (
	renameFile = os.Rename
	syncFile   = (*os.File).Sync
	linkFile   = os.Link
)

// SyncFile flushes the file at path to disk. A file that is about to be renamed
// or linked into place is flushed first, so the name never outlives its bytes
// across a power cut.
func SyncFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	if err := f.Sync(); err != nil {
		_ = f.Close()
		return err
	}
	return f.Close()
}

// SyncDir flushes dir's entries to disk, so a file just renamed, linked or
// created in it is still there after a power cut. A filesystem that cannot sync
// a directory reports EINVAL; there is nothing more to flush on one of those,
// so that is not an error.
func SyncDir(dir string) error {
	d, err := os.Open(dir)
	if err != nil {
		return err
	}
	if err := d.Sync(); err != nil && !errors.Is(err, syscall.EINVAL) {
		_ = d.Close()
		return err
	}
	return d.Close()
}

// copyIntoPlace copies the file at src to dst through [WriteFileAtomic], for a
// move that cannot rename or link across the two.
func copyIntoPlace(src, dst string) error {
	f, err := os.Open(src)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	return WriteFileAtomic(dst, f)
}
