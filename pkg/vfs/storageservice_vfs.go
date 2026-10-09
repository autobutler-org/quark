package vfs

import (
	"context"
	"io"
	"io/fs"
	"mime"
	"os"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// serialSet builds a set from a slice for O(1) lookup.
func serialSet(serials []string) map[string]bool {
	set := make(map[string]bool, len(serials))
	for _, s := range serials {
		set[s] = true
	}
	return set
}

// List returns the contents of the given directory path on this namespace's
// device. The internal namespace covers every managed device without a serial,
// deduplicating folders between them; [ListDevices] is the listing across
// every device.
//
// filter.Recursive walks the whole subtree. It used to be silently ignored:
// the implementation always delegated to storageutil.StatFilesInDir, a
// single-level os.ReadDir, so every caller asking for a recursive listing —
// the Docs page, Recent files, filename search, folder download — only ever
// saw files sitting at the storage root (#1605).
func (v *StorageServiceVFS) List(ctx context.Context, path string, filter *ListFilter) ([]FileInfo, error) {
	devices, err := v.svc.GetManagedRoots()
	if err != nil {
		return nil, err
	}

	// Build serial filter set once (empty map = no filter).
	var allowedSerials map[string]bool
	if filter != nil && len(filter.SerialFilter) > 0 {
		allowedSerials = serialSet(filter.SerialFilter)
	}

	recursive := filter != nil && filter.Recursive
	maxResults := 0
	if filter != nil {
		maxResults = filter.MaxResults
	}

	// Deduplicate directories (keep first occurrence, show all files). Keyed by
	// the path relative to the listing root rather than the base name, so two
	// distinct subfolders that happen to share a name survive a recursive walk.
	seenDirs := make(map[string]bool)
	out := make([]FileInfo, 0)

	full := func() bool { return maxResults > 0 && len(out) >= maxResults }

	// add applies dedup and the per-entry filters. Filtering happens here, as
	// each entry is produced, so MaxResults can stop a recursive walk instead of
	// materializing the whole library and truncating afterwards.
	add := func(f storageutil.WalkedFile) {
		if f.Info.IsDir() {
			if seenDirs[f.RelPath] {
				return
			}
			seenDirs[f.RelPath] = true
		}
		fi := deviceFileInfoToVFS(f.Info, v.namespaceID, path, f.RelPath)
		if !matchesFilter(fi, filter) {
			return
		}
		out = append(out, fi)
	}

	sawListing := false
	sawNotFound := false

	for _, device := range devices {
		if full() {
			break
		}
		serial := rootSerial(device)
		if serial != v.serial || (allowedSerials != nil && !allowedSerials[serial]) {
			continue
		}
		fullDir, err := storageutil.SafeJoin(device.FilesDir, path)
		if err != nil {
			continue
		}

		err = v.listDevice(ctx, fullDir, device, serial, recursive, add, full)
		if err != nil {
			if ctx != nil && ctx.Err() != nil {
				return nil, ctx.Err()
			}
			if path != "" {
				sawNotFound = true
			}
			continue
		}
		sawListing = true
	}

	if path != "" && sawNotFound && !sawListing {
		return nil, ErrNotFound
	}

	return out, nil
}

// listDevice feeds one device's entries under fullDir to add, walking the whole
// subtree when recursive is set and stopping as soon as full reports the result
// budget is spent.
func (v *StorageServiceVFS) listDevice(
	ctx context.Context,
	fullDir string,
	device storageutil.ManagedDevice,
	serial string,
	recursive bool,
	add func(storageutil.WalkedFile),
	full func() bool,
) error {
	if !recursive {
		files, err := storageutil.StatFilesInDir(fullDir, device.Name, device.DataDir, serial)
		if err != nil {
			return err
		}
		for _, f := range files {
			if full() {
				break
			}
			// At a single level the relative path is just the entry name.
			add(storageutil.WalkedFile{Info: f, RelPath: f.Name()})
		}
		return nil
	}

	return storageutil.WalkFilesInDir(ctx, fullDir, device.Name, device.DataDir, serial,
		func(f storageutil.WalkedFile) error {
			add(f)
			if full() {
				return fs.SkipAll
			}
			return nil
		},
	)
}

// matchesFilter applies the per-entry filters. AfterPath and MimePrefix were
// both declared on ListFilter and honored by other implementations while this
// one dropped them, the same way it dropped Recursive (#1605).
func matchesFilter(fi FileInfo, filter *ListFilter) bool {
	if filter == nil {
		return true
	}
	if filter.AfterPath != "" && fi.Path <= filter.AfterPath {
		return false
	}
	// Directories have no meaningful MIME type, so a MIME filter never applies
	// to them — matching LocalVFS, which lets directories through.
	if filter.MimePrefix != "" && !fi.IsDir && !strings.HasPrefix(fi.MimeType, filter.MimePrefix) {
		return false
	}
	return true
}

// filesDir resolves the base directory for this namespace, preferring the
// managed device's files directory over the default. StatFile, DownloadFile,
// and DeleteFiles all resolve this way internally; this exists so the paths
// derived directly in this file agree with them. Only the internal namespace
// has a default: a device namespace whose device is gone is [ErrNotFound].
func (v *StorageServiceVFS) filesDir() (string, error) {
	device, err := v.svc.FindManagedDeviceBySerial(v.serial)
	if err != nil {
		return "", err
	}
	if device != nil && device.FilesDir != "" {
		return device.FilesDir, nil
	}
	if v.serial != "" {
		return "", ErrNotFound
	}
	return storageutil.GetFilesDir()
}

// attached reports ErrNotFound when this is a device namespace and its device
// is no longer managed. The StorageService resolves an unknown serial to the
// default files directory, so every single-path operation asks first rather
// than let a stale namespace reach the internal drive (#2639).
func (v *StorageServiceVFS) attached() error {
	if v.serial == "" {
		return nil
	}
	device, err := v.svc.FindManagedDeviceBySerial(v.serial)
	if err != nil {
		return err
	}
	if device == nil {
		return ErrNotFound
	}
	return nil
}

// mimeTypeForName returns the MIME type for a file name. Image formats
// (including HEIC/HEIF/TIFF/BMP, which Go's stdlib mime package doesn't
// recognize — see #1567) are resolved via storageutil's own extension table
// rather than mime.TypeByExtension, which returns "" for them and silently
// disables server-side JPEG conversion for image previews.
func mimeTypeForName(name string) string {
	ext := filepath.Ext(name)
	switch storageutil.DetermineFileTypeFromPath(name) {
	case storageutil.FileTypeImage, storageutil.FileTypeSvg:
		return storageutil.ImageMIMETypeFromExtension(ext)
	}
	return mime.TypeByExtension(ext)
}

// Stat returns metadata for a single path. Only a path that does not exist
// is [ErrNotFound]; a permission failure is [ErrPermissionDenied] (#2640). A
// ".trash/..." path names something in the trash (see [Trasher]).
func (v *StorageServiceVFS) Stat(_ context.Context, path string) (FileInfo, error) {
	absPath, err := v.resolveRead(path)
	if err != nil {
		return FileInfo{}, err
	}
	fi, err := os.Stat(absPath)
	if err != nil {
		return FileInfo{}, hostErr(err)
	}
	info := FileInfo{
		Name:         fi.Name(),
		Path:         cleanPath(path),
		IsDir:        fi.IsDir(),
		Size:         fi.Size(),
		ModTime:      fi.ModTime(),
		MimeType:     mimeTypeForName(fi.Name()),
		Namespace:    v.namespaceID,
		DeviceSerial: v.serial,
	}
	// The device fields read the way List reports them, so a caller that
	// stats a path it found elsewhere — a filename index hit — can show
	// which device it is on (#2642).
	if device, err := v.svc.FindManagedDeviceBySerial(v.serial); err == nil && device != nil {
		info.DeviceName = device.Name
		info.DevicePath = device.DataDir
	}
	return info, nil
}

// Open returns the file at the given path. It resolves the path the way Stat
// and Write do, against the managed device's files directory, which may differ
// from the default one — see #1538, where re-deriving from GetFilesDir() made
// Stat and Open disagree and downloads returned an empty body. A directory is
// [ErrIsDirectory]. A ".trash/..." path opens something in the trash, the way
// Stat finds it.
func (v *StorageServiceVFS) Open(_ context.Context, path string) (File, error) {
	absPath, err := v.resolveRead(path)
	if err != nil {
		return nil, err
	}
	return hostOpen(absPath)
}

// Write writes a file into the files directory of the managed device that
// backs this namespace. The internal namespace falls back to the default files
// directory when no device is present; a device namespace does not. Resolving
// the same way Stat and Open do keeps a written file findable by a subsequent
// read (#1538).
//
// The bytes stream into a temp file beside the destination and are renamed
// into place: writing straight to the real name put a growing, half-written
// file in every listing for the length of an upload (#1828). With IfNoneMatch
// "*" a taken name is refused in the same step (#2640).
func (v *StorageServiceVFS) Write(_ context.Context, path string, r io.Reader, opts WriteOptions) error {
	absPath, err := v.resolve(path)
	if err != nil {
		return err
	}
	return hostWrite(absPath, r, opts)
}

// MoveFileIn places the host file at srcAbs at path, renaming it rather than
// copying it when it can. See [FileMover].
func (v *StorageServiceVFS) MoveFileIn(ctx context.Context, srcAbs string, path string, opts WriteOptions) error {
	absPath, err := v.resolve(path)
	if err != nil {
		return err
	}
	return moveFileIn(srcAbs, absPath, opts, func(r io.Reader) error {
		return v.Write(ctx, path, r, opts)
	})
}

// resolve turns a namespace path into the host path under this namespace's
// files directory, for an operation that changes it. A path escaping it is
// [ErrPermissionDenied], and so is a ".trash/..." path: the trash changes
// only through [Trasher]. A device namespace whose device is gone is
// [ErrNotFound].
func (v *StorageServiceVFS) resolve(path string) (string, error) {
	if storageutil.IsTrashPath(cleanPath(path)) {
		return "", ErrPermissionDenied
	}
	return v.resolveRead(path)
}

// resolveRead is resolve for an operation that only reads: a ".trash/..."
// path resolves into the device's trash, which sits beside its files
// directory (#2173), the way access, search and thumbnail rows address a
// trashed item.
func (v *StorageServiceVFS) resolveRead(path string) (string, error) {
	filesDir, err := v.filesDir()
	if err != nil {
		return "", err
	}
	if rel := cleanPath(path); storageutil.IsTrashPath(rel) {
		trashPath, err := storageutil.JoinTrashPath(filesDir, rel)
		if err != nil {
			return "", ErrPermissionDenied
		}
		return trashPath, nil
	}
	// filepath.Clean before SafeJoin so static analyzers (CodeQL go/path-injection)
	// can follow the traversal guard rather than seeing tainted data reach the disk.
	safePath, err := storageutil.SafeJoin(filesDir, filepath.Clean(path))
	if err != nil {
		return "", ErrPermissionDenied
	}
	return filepath.Clean(safePath), nil
}

// Delete removes the file or directory at path. A directory with entries is
// [ErrNotEmpty] unless opts.Recursive is set, and the namespace root is
// [ErrPermissionDenied].
func (v *StorageServiceVFS) Delete(_ context.Context, path string, opts DeleteOptions) error {
	if cleanPath(path) == "" {
		return ErrPermissionDenied
	}
	absPath, err := v.resolve(path)
	if err != nil {
		return err
	}
	return hostDelete(absPath, opts)
}

// MkdirAll creates a directory (and parents) in the vault.
func (v *StorageServiceVFS) MkdirAll(_ context.Context, path string) error {
	if err := v.attached(); err != nil {
		return err
	}
	dir, name := filepath.Split(strings.TrimRight(path, "/"))
	_, err := v.svc.CreateFolder(storageutil.CreateFolderParams{
		FolderDir:    dir,
		FolderName:   name,
		DeviceSerial: v.serial,
	})
	return err
}

// Move renames src to dst on this namespace's device via the StorageService.
func (v *StorageServiceVFS) Move(_ context.Context, src, dst string) error {
	if err := v.attached(); err != nil {
		return err
	}
	_, err := v.svc.MoveFile(storageutil.MoveFileParams{
		OldFilePath:     src,
		NewFilePath:     dst,
		OldDeviceSerial: v.serial,
		NewDeviceSerial: v.serial,
	})
	return err
}

// Copy copies the file at src to dst through Write. See [VFS.Copy].
func (v *StorageServiceVFS) Copy(ctx context.Context, src, dst string, opts CopyOptions) error {
	return copyFile(ctx, v, src, v, dst, opts)
}

// HostPath returns the host path of path on this namespace's device, in the
// trash for a ".trash/..." path. A device namespace whose device is gone is
// [ErrNotFound]. See [HostPather].
func (v *StorageServiceVFS) HostPath(_ context.Context, path string) (string, error) {
	return v.resolveRead(path)
}

// Watch is not supported by this implementation.
func (v *StorageServiceVFS) Watch(_ context.Context, _ string) (<-chan WatchEvent, error) {
	return nil, ErrWatchNotSupported
}

// deviceFileInfoToVFS converts a storageutil.DeviceFileInfo to a vfs.FileInfo.
// relPath is the entry's path relative to the listing root — the entry name for
// a single-level listing, "sub/deep.qdoc" for a recursive one. Callers such as
// the folder-download zip builder trim the requested path off Path to get an
// archive-relative name, so it has to carry the full subtree path.
func deviceFileInfoToVFS(f *storageutil.DeviceFileInfo, nsID, dirPath, relPath string) FileInfo {
	mimeType := mimeTypeForName(f.Name())
	return FileInfo{
		Name:      f.Name(),
		Path:      cleanPath(filepath.Join(dirPath, relPath)),
		Size:      f.Size(),
		IsDir:     f.IsDir(),
		MimeType:  mimeType,
		ModTime:   f.ModTime(),
		Namespace: nsID,

		DeviceSerial: f.DeviceSerial,
		DeviceName:   f.DeviceName,
		DevicePath:   f.DevicePath,
	}
}
