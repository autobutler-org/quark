package vfs

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"time"

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

// hostMove renames src to dst under filesDir, creating dst's folder first.
// Across filesystems, where a rename cannot go, it copies and then removes
// the source.
func hostMove(filesDir, src, dst string) error {
	oldFullPath, err := storageutil.SafeJoin(filesDir, src)
	if err != nil {
		return fmt.Errorf("invalid old file path: %w", err)
	}
	newFullPath, err := storageutil.SafeJoin(filesDir, dst)
	if err != nil {
		return fmt.Errorf("invalid new file path: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(newFullPath), 0755); err != nil {
		return fmt.Errorf("failed to create directory: %w", err) // coverage: ignore - requires filesystem permission errors
	}

	err = os.Rename(oldFullPath, newFullPath)
	if linkErr, ok := err.(*os.LinkError); ok && linkErr.Err.Error() == "invalid cross-device link" { // coverage: ignore - requires a cross-device move
		return moveAcrossDevices(oldFullPath, newFullPath)
	}
	if err != nil {
		return fmt.Errorf("failed to move file: %w", err) // coverage: ignore - requires filesystem permission errors
	}
	return nil
}

// moveAcrossDevices copies the file at oldFullPath to newFullPath and removes
// the original, for a move a rename cannot make.
func moveAcrossDevices(oldFullPath, newFullPath string) error {
	srcFile, err := os.Open(oldFullPath)
	if err != nil {
		return fmt.Errorf("failed to open source file for cross-device move: %w", err)
	}
	defer srcFile.Close()

	dstFile, err := os.Create(newFullPath)
	if err != nil {
		return fmt.Errorf("failed to create destination file for cross-device move: %w", err)
	}
	defer dstFile.Close()

	if _, err := io.Copy(dstFile, srcFile); err != nil {
		return fmt.Errorf("failed to copy file for cross-device move: %w", err)
	}
	if err := os.Remove(oldFullPath); err != nil {
		return fmt.Errorf("failed to remove source file after cross-device move: %w", err)
	}
	return nil
}

// hostMkdirAll creates the folder at rel under filesDir, and its parents.
func hostMkdirAll(filesDir, rel string) error {
	fullPath, err := storageutil.SafeJoin(filesDir, rel)
	if err != nil {
		return fmt.Errorf("invalid folder path: %w", err)
	}
	if err := os.MkdirAll(fullPath, 0755); err != nil {
		return fmt.Errorf("failed to create folder: %w", err) // coverage: ignore - requires filesystem permission errors
	}
	return nil
}

// hostListDir lists dir one level deep, directories first and then by name,
// skipping Quark's own bookkeeping. A directory reports the size of
// everything under it.
func hostListDir(dir string, deviceName string, devicePath string, deviceSerial string) ([]*storageutil.DeviceFileInfo, error) {
	entries, err := os.ReadDir(dir)
	files := make([]*storageutil.DeviceFileInfo, 0, len(entries))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("%w: %s", storageutil.ErrPathNotFound, dir)
		}
		return nil, fmt.Errorf("error reading the directory %s: %w", dir, err) // coverage: ignore - requires filesystem permission errors
	}
	for _, entry := range entries {
		if storageutil.IsInternalName(entry.Name()) {
			continue
		}
		var fileInfo fs.FileInfo
		fullPath := filepath.Join(dir, entry.Name())
		if entry.IsDir() {
			folderSize, err := storageutil.GetFolderSize(fullPath)
			if err != nil {
				return nil, fmt.Errorf("error getting size for folder %s: %w", entry.Name(), err) // coverage: ignore - requires filesystem errors during folder traversal
			}
			fileInfo = storageutil.NewCustomFileInfo().WithName(entry.Name()).WithSize(folderSize)
		} else {
			info, err := entry.Info()
			if err != nil {
				return nil, fmt.Errorf("error getting info for file %s: %w", entry.Name(), err) // coverage: ignore - requires filesystem errors on stat
			}
			fileInfo = info
		}
		// Wrap in DeviceFileInfo with device info
		files = append(files, storageutil.NewDeviceFileInfo(fileInfo, deviceName, devicePath, fullPath, deviceSerial))
	}
	// Sort files by directory first, then by name
	slices.SortFunc(files, func(a, b *storageutil.DeviceFileInfo) int {
		if a.IsDir() && !b.IsDir() {
			return -1 // a is a directory, b is a file
		} else if !a.IsDir() && b.IsDir() {
			return 1 // coverage: ignore - a is a file, b is a directory
		}
		return strings.Compare(a.Name(), b.Name())
	})
	return files, nil
}

// hostWalkDir recursively walks dir and calls visit for every entry beneath
// it, in lexical order, parents before children. The root itself is not
// visited.
//
// visit may return fs.SkipDir to skip the current directory's contents or
// fs.SkipAll to stop the walk; both are reported as success. Any other error
// stops the walk and is returned.
//
// Symlinks are reported but never followed, so the walk cannot escape dir or
// loop — the same containment the single-level hostListDir listing has.
//
// Directory entries carry the filesystem's own size rather than the size of
// their contents. hostListDir computes subtree sizes with storageutil.GetFolderSize,
// which is a full walk per directory and so quadratic when the caller is
// already walking; LocalVFS reports raw directory sizes for the same reason.
func hostWalkDir(
	ctx context.Context,
	dir string,
	deviceName string,
	devicePath string,
	deviceSerial string,
	visit func(walkedFile) error,
) error {
	root := filepath.Clean(dir)
	if _, err := os.Stat(root); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("%w: %s", storageutil.ErrPathNotFound, dir)
		}
		return fmt.Errorf("error reading the directory %s: %w", dir, err)
	}

	return filepath.WalkDir(root, func(fullPath string, entry fs.DirEntry, err error) error {
		if err != nil {
			// An unreadable subdirectory must not abort the whole listing —
			// skip it and keep walking the rest of the tree.
			if entry != nil && entry.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if ctx != nil && ctx.Err() != nil {
			return ctx.Err()
		}
		if fullPath == root {
			return nil
		}

		rel, relErr := filepath.Rel(root, fullPath)
		if relErr != nil {
			return nil // coverage: ignore - WalkDir only yields paths under root
		}
		rel = filepath.ToSlash(rel)

		if storageutil.IsInternalName(entry.Name()) {
			if entry.IsDir() {
				return fs.SkipDir
			}
			return nil
		}

		info, infoErr := entry.Info()
		if infoErr != nil {
			// The entry vanished mid-walk; nothing to report for it.
			return nil // coverage: ignore - requires a concurrent delete
		}

		return visit(walkedFile{
			Info:    storageutil.NewDeviceFileInfo(info, deviceName, devicePath, fullPath, deviceSerial),
			RelPath: rel,
		})
	})
}

// trashMetaSuffix ends the name of the JSON sidecar written beside each
// trashed item.
const trashMetaSuffix = ".meta.json"

// trashStampLayout is the UTC timestamp every trash name starts with.
const trashStampLayout = "20060102T150405Z"

// maxTrashNameBytes keeps a trash name and its sidecar under the 255-byte file
// name limit every filesystem Quark runs on shares.
const maxTrashNameBytes = 255 - len(trashMetaSuffix)

// writeTrashSidecar writes a trashed item's sidecar. A test swaps it to stand
// in for a write that fails.
var writeTrashSidecar = storageutil.WriteFileAtomicPerm

// trashMetaFile returns the path of the JSON metadata sidecar for a trashed item.
func trashMetaFile(trashItemPath string) string {
	return trashItemPath + trashMetaSuffix
}

// joinTrashPath returns where a TrashPath of filesDir's trash sits on disk. A
// path that is not a TrashPath, or that climbs out of the trash, is an error.
func joinTrashPath(filesDir, trashPath string) (string, error) {
	if !storageutil.IsTrashPath(trashPath) {
		return "", fmt.Errorf("not a trash path: %s", trashPath)
	}
	inside := strings.TrimPrefix(filepath.ToSlash(filepath.Clean(trashPath)), storageutil.TrashPathPrefix)
	return storageutil.SafeJoin(storageutil.TrashRoot(filesDir), filepath.FromSlash(inside))
}

// openTrash returns filesDir's trash root, first moving in whatever is still
// in the hidden <filesDir>/.trash that held the trash before #2173, sidecars
// included. Every trash operation opens the trash this way, so a device's old
// trash moves the first time it is touched: at startup, by the purge, for
// every device mounted then, and on first use for one plugged in later.
func openTrash(filesDir string) (string, error) {
	root := storageutil.TrashRoot(filesDir)
	old := filepath.Join(filesDir, storageutil.TrashPathPrefix)
	// Lstat, so a symlink planted under the old name is never followed.
	if info, err := os.Lstat(old); err != nil || !info.IsDir() {
		return root, nil
	}
	entries, err := os.ReadDir(old)
	if err != nil {
		return root, fmt.Errorf("failed to read the old trash directory: %w", err) // coverage: ignore - requires filesystem permission errors
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return root, fmt.Errorf("failed to create trash directory: %w", err) // coverage: ignore - requires filesystem permission errors
	}
	for _, entry := range entries {
		dest := filepath.Join(root, entry.Name())
		// Trash names carry a random suffix, so a clash means both trashes
		// already hold this item; the old copy stays put, still hidden, rather
		// than be overwritten.
		if _, err := os.Lstat(dest); err == nil {
			continue
		}
		if err := os.Rename(filepath.Join(old, entry.Name()), dest); err != nil && !os.IsNotExist(err) {
			return root, fmt.Errorf("failed to move %s out of the old trash directory: %w", entry.Name(), err) // coverage: ignore - requires filesystem errors
		}
	}
	_ = os.Remove(old) // only succeeds once it is empty
	return root, nil
}

// newTrashName builds a trash name that cannot collide with another item
// trashed in the same second: a timestamp, a random suffix, and the original
// base name, which is truncated if the three would overflow a file name.
func newTrashName(base string, now time.Time) (string, error) {
	var random [8]byte
	if _, err := rand.Read(random[:]); err != nil {
		return "", fmt.Errorf("failed to generate trash name: %w", err) // coverage: ignore - crypto/rand does not fail on supported platforms
	}
	prefix := now.UTC().Format(trashStampLayout) + "_" + hex.EncodeToString(random[:]) + "_"
	if room := maxTrashNameBytes - len(prefix); len(base) > room {
		base = strings.ToValidUTF8(base[:room], "")
	}
	return prefix + base, nil
}

// hostTrash moves paths, relative to opts.RootDir, into filesDir's trash. A
// path that no longer exists is skipped, so a repeated delete succeeds the way
// it did when deletes were permanent. When it fails partway it still lists
// what was moved before the failure.
func hostTrash(filesDir string, paths []string, opts TrashOptions) ([]TrashedItem, error) {
	var trashed []TrashedItem
	trashRoot, err := openTrash(filesDir)
	if err != nil {
		return trashed, err
	}
	if err := os.MkdirAll(trashRoot, 0o700); err != nil {
		return trashed, fmt.Errorf("failed to create trash directory: %w", err)
	}

	for _, filePath := range paths {
		fullPath, err := storageutil.SafeJoin(filesDir, opts.RootDir, filePath)
		if err != nil {
			return trashed, fmt.Errorf("invalid file path: %w", err)
		}
		relOriginal, err := filepath.Rel(filepath.Clean(filesDir), fullPath)
		if err != nil || relOriginal == "." || storageutil.IsTrashPath(relOriginal) {
			return trashed, fmt.Errorf("invalid file path: %s", filePath)
		}
		if _, err := os.Lstat(fullPath); os.IsNotExist(err) {
			continue
		}

		now := time.Now().UTC()
		trashName, err := newTrashName(filepath.Base(fullPath), now)
		if err != nil {
			return trashed, err // coverage: ignore - crypto/rand does not fail on supported platforms
		}
		trashDest := filepath.Join(trashRoot, trashName)

		if err := os.Rename(fullPath, trashDest); err != nil {
			return trashed, fmt.Errorf("failed to move %s to trash: %w", filePath, err)
		}

		// The sidecar is the only record of where the item came from. Without
		// it the item could never be restored, so put the item back rather
		// than leave it stranded in the trash.
		originalPath := filepath.ToSlash(relOriginal)
		metaBytes, _ := json.Marshal(TrashEntry{
			OriginalPath: originalPath,
			TrashedAt:    now,
			TrashedBy:    opts.TrashedBy,
		})
		if err := writeTrashSidecar(trashMetaFile(trashDest), bytes.NewReader(metaBytes), 0o600); err != nil {
			_ = os.Rename(trashDest, fullPath)
			return trashed, fmt.Errorf("failed to record trash metadata for %s: %w", filePath, err)
		}
		trashed = append(trashed, TrashedItem{OriginalPath: originalPath, TrashName: trashName})
	}

	return trashed, nil
}

// hostListTrash lists filesDir's trash, most recently trashed first. It never returns a nil
// slice, so an empty trash serializes as [].
func hostListTrash(filesDir string) ([]TrashItem, error) {
	trashRoot, err := openTrash(filesDir)
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(trashRoot)
	items := make([]TrashItem, 0, len(entries))
	if os.IsNotExist(err) {
		return items, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to read trash directory: %w", err)
	}

	names := make(map[string]bool, len(entries))
	for _, entry := range entries {
		names[entry.Name()] = true
	}

	for _, entry := range entries {
		name := entry.Name()
		if isTrashSidecar(name, names) {
			continue
		}
		fullPath := filepath.Join(trashRoot, name)
		info, err := entry.Info()
		if err != nil {
			continue // coverage: ignore - requires a concurrent purge
		}

		item := TrashItem{TrashName: name, Name: name, IsDir: entry.IsDir(), Size: info.Size()}
		if item.IsDir {
			// The trash only holds what users deleted, so walking a trashed
			// folder is bounded by that; a folder that cannot be walked reports 0.
			item.Size, _ = storageutil.GetFolderSize(fullPath)
		}
		meta, metaErr := readTrashEntry(fullPath)
		if metaErr == nil {
			item.OriginalPath = meta.OriginalPath
			item.Name = filepath.Base(meta.OriginalPath)
			item.TrashedBy = meta.TrashedBy
		}
		item.TrashedAt = trashedAt(name, meta, info.ModTime())
		item.ExpiresAt = item.TrashedAt.AddDate(0, 0, storageutil.TrashRetentionDays)
		items = append(items, item)
	}

	slices.SortFunc(items, func(a, b TrashItem) int {
		if c := b.TrashedAt.Compare(a.TrashedAt); c != 0 {
			return c
		}
		return strings.Compare(a.TrashName, b.TrashName)
	})
	return items, nil
}

// isTrashSidecar reports whether a trash entry is the metadata of another
// entry. Checking the suffix alone would hide a trashed file the user named
// "report.json" or even "x.meta.json"; a sidecar also has its item beside it.
func isTrashSidecar(name string, names map[string]bool) bool {
	item, ok := strings.CutSuffix(name, trashMetaSuffix)
	return ok && names[item]
}

// readTrashEntry reads the sidecar of the trashed item at itemPath.
func readTrashEntry(itemPath string) (TrashEntry, error) {
	var meta TrashEntry
	metaBytes, err := os.ReadFile(trashMetaFile(itemPath))
	if err != nil {
		return meta, err
	}
	if err := json.Unmarshal(metaBytes, &meta); err != nil {
		return meta, fmt.Errorf("corrupt trash metadata: %w", err)
	}
	return meta, nil
}

// trashedAt reports when an item was trashed: from its sidecar, else from the
// timestamp its trash name starts with, else from its modification time. A
// rename keeps a file's own mtime, so mtime is the last resort — it can make
// a long-unedited file look long-trashed.
func trashedAt(trashName string, meta TrashEntry, modTime time.Time) time.Time {
	if !meta.TrashedAt.IsZero() {
		return meta.TrashedAt
	}
	if len(trashName) >= len(trashStampLayout) {
		if t, err := time.Parse(trashStampLayout, trashName[:len(trashStampLayout)]); err == nil {
			return t
		}
	}
	return modTime.UTC()
}

// resolveTrashItem validates a trash name from a request and returns the path
// of the item it names. The name crosses a trust boundary, so it must be a
// single path element that exists in the trash and is not a sidecar.
func resolveTrashItem(trashRoot, name string) (string, error) {
	if name == "" || name == "." || name == ".." ||
		strings.ContainsRune(name, '/') || strings.ContainsRune(name, filepath.Separator) {
		return "", fmt.Errorf("%w: %q", storageutil.ErrInvalidTrashName, name)
	}
	itemPath := filepath.Join(trashRoot, name)
	if _, err := os.Lstat(itemPath); err != nil {
		return "", fmt.Errorf("%w: %s", storageutil.ErrTrashItemNotFound, name)
	}
	if item, ok := strings.CutSuffix(name, trashMetaSuffix); ok {
		if _, err := os.Lstat(filepath.Join(trashRoot, item)); err == nil {
			return "", fmt.Errorf("%w: %s", storageutil.ErrTrashItemNotFound, name)
		}
	}
	return itemPath, nil
}

// hostReadTrashEntry reads the sidecar of the item trashName names in
// filesDir's trash, validating the name the way restore and delete do, so a
// caller can decide who may act on the item before anything is touched
// (#1905). An item whose sidecar is missing comes back with the zero entry: no
// original location and nobody recorded as having trashed it.
func hostReadTrashEntry(filesDir, trashName string) (TrashEntry, error) {
	trashRoot, err := openTrash(filesDir)
	if err != nil {
		return TrashEntry{}, err
	}
	itemPath, err := resolveTrashItem(trashRoot, trashName)
	if err != nil {
		return TrashEntry{}, err
	}
	entry, err := readTrashEntry(itemPath)
	if err != nil && !os.IsNotExist(err) {
		return TrashEntry{}, err
	}
	return entry, nil
}

// resolveTrashRef validates a reference from a request. Its path crosses a
// trust boundary like its name does, so it must stay inside the trashed item:
// no absolute path, no "..", and no symlink on the way that leads out.
func resolveTrashRef(trashRoot string, ref TrashRef) (resolvedTrashRef, error) {
	itemPath, err := resolveTrashItem(trashRoot, ref.TrashName)
	if err != nil {
		return resolvedTrashRef{}, err
	}
	resolved := resolvedTrashRef{itemPath: itemPath, target: itemPath}
	if ref.Path == "" {
		return resolved, nil
	}
	rel := filepath.Clean(filepath.FromSlash(ref.Path))
	if !filepath.IsLocal(rel) {
		return resolvedTrashRef{}, fmt.Errorf("%w: %q", storageutil.ErrInvalidTrashPath, ref.Path)
	}
	if rel == "." {
		return resolved, nil
	}
	// Only a real folder has anything inside it. Lstat, so a trashed symlink
	// to a folder elsewhere is not followed.
	if info, err := os.Lstat(itemPath); err != nil || !info.IsDir() {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s/%s", storageutil.ErrTrashItemNotFound, ref.TrashName, ref.Path)
	}
	target := filepath.Join(itemPath, rel)
	realItem, err := filepath.EvalSymlinks(itemPath)
	if err != nil {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s", storageutil.ErrTrashItemNotFound, ref.TrashName) // coverage: ignore - requires a concurrent purge
	}
	realParent, err := filepath.EvalSymlinks(filepath.Dir(target))
	if err != nil {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s/%s", storageutil.ErrTrashItemNotFound, ref.TrashName, ref.Path)
	}
	if !isWithin(realItem, realParent) {
		return resolvedTrashRef{}, fmt.Errorf("%w: %q", storageutil.ErrInvalidTrashPath, ref.Path)
	}
	if _, err := os.Lstat(target); err != nil {
		return resolvedTrashRef{}, fmt.Errorf("%w: %s/%s", storageutil.ErrTrashItemNotFound, ref.TrashName, ref.Path)
	}
	resolved.target = target
	resolved.rel = filepath.ToSlash(rel)
	return resolved, nil
}

// isWithin reports whether path is dir or somewhere inside it. Both must be
// clean.
func isWithin(dir, path string) bool {
	return path == dir || strings.HasPrefix(path, dir+string(filepath.Separator))
}

// hostListTrashContents lists a folder in filesDir's trash: the trashed folder
// params names, or a folder inside it. It never returns a nil slice, so an
// empty folder serializes as [].
func hostListTrashContents(filesDir string, params TrashRef) (TrashContents, error) {
	trashRoot, err := openTrash(filesDir)
	if err != nil {
		return TrashContents{}, err
	}
	ref, err := resolveTrashRef(trashRoot, params)
	if err != nil {
		return TrashContents{}, err
	}
	itemInfo, err := os.Lstat(ref.itemPath)
	if err != nil {
		return TrashContents{}, fmt.Errorf("%w: %s", storageutil.ErrTrashItemNotFound, params.TrashName) // coverage: ignore - requires a concurrent purge
	}
	if info, err := os.Lstat(ref.target); err != nil || !info.IsDir() {
		return TrashContents{}, fmt.Errorf("%w: %s/%s", storageutil.ErrNotATrashFolder, params.TrashName, params.Path)
	}
	entries, err := os.ReadDir(ref.target)
	if err != nil {
		return TrashContents{}, fmt.Errorf("failed to read trashed folder: %w", err) // coverage: ignore - requires filesystem permission errors
	}

	result := TrashContents{Items: make([]storageutil.TrashContentsItem, 0, len(entries))}
	meta, metaErr := readTrashEntry(ref.itemPath)
	if metaErr == nil {
		result.OriginalPath = path.Join(meta.OriginalPath, ref.rel)
	}
	result.ExpiresAt = trashedAt(params.TrashName, meta, itemInfo.ModTime()).AddDate(0, 0, storageutil.TrashRetentionDays)

	for _, entry := range entries {
		if storageutil.IsInternalName(entry.Name()) {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue // coverage: ignore - requires a concurrent purge
		}
		child := storageutil.TrashContentsItem{
			Name:       entry.Name(),
			Path:       path.Join(ref.rel, entry.Name()),
			IsDir:      entry.IsDir(),
			Size:       info.Size(),
			ModifiedAt: info.ModTime().UTC(),
		}
		if child.IsDir {
			// Bounded by what users deleted, like the trash listing; a folder
			// that cannot be walked reports 0.
			child.Size, _ = storageutil.GetFolderSize(filepath.Join(ref.target, entry.Name()))
		}
		result.Items = append(result.Items, child)
	}
	return result, nil
}

// hostRestoreTrash moves trashed items in filesDir's trash back to their
// original locations. Every item is checked
// before any is moved, so a batch that would conflict or names something
// unknown changes nothing. It never overwrites: an occupied original path, or
// two items in the batch landing on the same path or one inside the other, is
// an ErrRestoreConflict.
//
// Something inside a trashed folder goes back to the folder's original path
// joined with its path inside it, and the folder stays in the trash with the
// rest of its contents.
func hostRestoreTrash(filesDir string, items []TrashRef) ([]RestoredItem, error) {
	trashRoot, err := openTrash(filesDir)
	if err != nil {
		return nil, err
	}

	type move struct {
		from, to, rel, source string
		// whole is true when the move takes the trashed item itself, and
		// with it the sidecar's reason to exist.
		whole bool
	}
	moves := make([]move, 0, len(items))
	for _, item := range items {
		ref, err := resolveTrashRef(trashRoot, item)
		if err != nil {
			return nil, err
		}
		meta, err := readTrashEntry(ref.itemPath)
		if err != nil {
			return nil, fmt.Errorf("%w: the original location of %s is unknown", storageutil.ErrRestoreConflict, item.TrashName)
		}
		restoreTo, err := storageutil.SafeJoin(filesDir, meta.OriginalPath)
		if err != nil || restoreTo == filepath.Clean(filesDir) || storageutil.IsTrashPath(meta.OriginalPath) {
			return nil, fmt.Errorf("%w: %s has an invalid original location", storageutil.ErrRestoreConflict, item.TrashName)
		}
		rel := path.Join(meta.OriginalPath, ref.rel)
		restoreTo = filepath.Join(restoreTo, filepath.FromSlash(ref.rel))
		if _, err := os.Lstat(restoreTo); err == nil {
			return nil, fmt.Errorf("%w: %s already exists", storageutil.ErrRestoreConflict, rel)
		}
		if err := checkRestoreParent(filesDir, restoreTo); err != nil {
			return nil, err
		}
		for _, m := range moves {
			if isWithin(m.to, restoreTo) || isWithin(restoreTo, m.to) {
				return nil, fmt.Errorf("%w: %s and %s overlap", storageutil.ErrRestoreConflict, m.rel, rel)
			}
		}
		moves = append(moves, move{
			from: ref.target, to: restoreTo, rel: rel, whole: ref.rel == "",
			source: storageutil.TrashPath(item.TrashName, ref.rel),
		})
	}

	var restored []RestoredItem
	for _, m := range moves {
		if err := os.MkdirAll(filepath.Dir(m.to), 0o700); err != nil {
			return restored, fmt.Errorf("failed to recreate the folder for %s: %w", m.rel, err)
		}
		// os.Rename replaces an existing file, so check again right before
		// it. A write landing between this Lstat and the rename can still be
		// overwritten; closing that needs renameat2(RENAME_NOREPLACE) on Linux
		// and renamex_np(RENAME_EXCL) on darwin behind build tags.
		if _, err := os.Lstat(m.to); err == nil {
			return restored, fmt.Errorf("%w: %s already exists", storageutil.ErrRestoreConflict, m.rel)
		}
		info, err := os.Lstat(m.from)
		if err != nil {
			return restored, fmt.Errorf("%w: %s", storageutil.ErrTrashItemNotFound, filepath.Base(m.from))
		}
		if err := os.Rename(m.from, m.to); err != nil {
			return restored, fmt.Errorf("failed to restore %s: %w", m.rel, err)
		}
		if m.whole {
			_ = os.Remove(trashMetaFile(m.from))
		}
		restored = append(restored, RestoredItem{Path: m.rel, IsDir: info.IsDir(), Source: m.source})
	}
	return restored, nil
}

// checkRestoreParent refuses a restore whose missing parent folders could not
// be recreated because a file now sits where one of them was.
func checkRestoreParent(filesDir, restoreTo string) error {
	root := filepath.Clean(filesDir)
	for dir := filepath.Dir(restoreTo); dir != root && isWithin(root, dir); dir = filepath.Dir(dir) {
		info, err := os.Stat(dir)
		if err != nil {
			continue // missing; the restore recreates it
		}
		if !info.IsDir() {
			rel, _ := filepath.Rel(root, dir)
			return fmt.Errorf("%w: %s is not a folder", storageutil.ErrRestoreConflict, filepath.ToSlash(rel))
		}
		return nil
	}
	return nil
}

// hostDeleteTrash permanently deletes the named items from filesDir's trash.
// Every reference is
// validated before anything is deleted. Something inside a trashed folder is
// deleted on its own; the folder stays in the trash.
func hostDeleteTrash(filesDir string, items []TrashRef) ([]string, error) {
	trashRoot, err := openTrash(filesDir)
	if err != nil {
		return nil, err
	}
	refs := make([]resolvedTrashRef, 0, len(items))
	for _, item := range items {
		ref, err := resolveTrashRef(trashRoot, item)
		if err != nil {
			return nil, err
		}
		refs = append(refs, ref)
	}

	var removed []string
	for _, ref := range refs {
		if ref.rel == "" {
			if err := removeTrashItem(ref.itemPath); err != nil {
				return removed, err
			}
		} else if err := os.RemoveAll(ref.target); err != nil {
			return removed, fmt.Errorf("failed to delete %s: %w", ref.rel, err)
		}
		removed = append(removed, storageutil.TrashPath(filepath.Base(ref.itemPath), ref.rel))
	}
	return removed, nil
}

// removeTrashItem deletes a trashed item and its sidecar.
func removeTrashItem(itemPath string) error {
	if err := os.RemoveAll(itemPath); err != nil {
		return fmt.Errorf("failed to delete %s: %w", filepath.Base(itemPath), err)
	}
	_ = os.Remove(trashMetaFile(itemPath))
	return nil
}

// hostEmptyTrash permanently deletes everything in filesDir's trash,
// returning each item it deleted as a TrashPath.
func hostEmptyTrash(filesDir string) ([]string, error) {
	return removeTrashItems(filesDir, func(TrashItem) bool { return true })
}

// hostPurgeExpiredTrash deletes the items in filesDir's trash that were
// trashed more than TrashRetentionDays before now, returning each one it
// deleted as a TrashPath.
func hostPurgeExpiredTrash(filesDir string, now time.Time) ([]string, error) {
	return removeTrashItems(filesDir, func(item TrashItem) bool {
		return !item.ExpiresAt.After(now)
	})
}

// removeTrashItems deletes every listed trash item doom picks, returning each
// one it deleted as a TrashPath.
func removeTrashItems(filesDir string, doom func(TrashItem) bool) ([]string, error) {
	items, err := hostListTrash(filesDir)
	if err != nil {
		return nil, err
	}
	trashRoot := storageutil.TrashRoot(filesDir) // hostListTrash opened it
	var removed []string
	for _, item := range items {
		if !doom(item) {
			continue
		}
		if err := removeTrashItem(filepath.Join(trashRoot, item.TrashName)); err != nil {
			return removed, err
		}
		removed = append(removed, storageutil.TrashPath(item.TrashName, ""))
	}
	return removed, nil
}
