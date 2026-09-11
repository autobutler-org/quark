package vfs

import (
	"context"
	"fmt"
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

// List returns the contents of the given directory path across all managed
// devices, deduplicating folders (same logic as the existing files
// listFilesImpl).
//
// filter.Recursive walks the whole subtree. It used to be silently ignored:
// the implementation always delegated to storageutil.StatFilesInDir, a
// single-level os.ReadDir, so every caller asking for a recursive listing —
// the Docs page, Recent files, filename search, folder download — only ever
// saw files sitting at the storage root (#1605).
func (v *StorageServiceVFS) List(ctx context.Context, path string, filter *ListFilter) ([]FileInfo, error) {
	devices, err := v.svc.GetManagedDevices()
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
		serial := ""
		if device.UsbInfo != nil {
			serial = device.UsbInfo.GetSerial()
		}
		// Apply serial filter.
		if allowedSerials != nil && !allowedSerials[serial] {
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
// derived directly in this file agree with them.
func (v *StorageServiceVFS) filesDir() (string, error) {
	device, err := v.svc.FindManagedDeviceBySerial("")
	if err != nil {
		return "", err
	}
	if device != nil && device.FilesDir != "" {
		return device.FilesDir, nil
	}
	return storageutil.GetFilesDir()
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

// Stat returns metadata for a single path.
func (v *StorageServiceVFS) Stat(_ context.Context, path string) (FileInfo, error) {
	result, err := v.svc.StatFile(storageutil.StatFileParams{FilePath: path})
	if err != nil {
		return FileInfo{}, ErrNotFound
	}
	mimeType := mimeTypeForName(result.Name)
	return FileInfo{
		Name:      result.Name,
		Path:      path,
		IsDir:     result.IsDir,
		Size:      result.Size,
		ModTime:   result.ModTime,
		MimeType:  mimeType,
		Namespace: v.namespaceID,
	}, nil
}

// Open returns a reader for the file at the given path.
func (v *StorageServiceVFS) Open(_ context.Context, path string) (io.ReadCloser, error) {
	result, err := v.svc.DownloadFile(storageutil.DownloadFileParams{FilePath: path})
	if err != nil {
		return nil, ErrNotFound
	}
	if result.IsFolder {
		return nil, ErrNotFound
	}
	// Use the path DownloadFile already resolved. It accounts for the managed
	// device's files directory, which may differ from the default one — see
	// #1538, where re-deriving from GetFilesDir() here made Stat and Open
	// disagree and downloads returned an empty body.
	//
	// DownloadFile validates via safeJoin internally; Clean again so static
	// analyzers (CodeQL go/path-injection) can follow the traversal guard
	// rather than seeing tainted data reach os.Open.
	safePath := filepath.Clean(result.FullPath)
	f, err := os.Open(safePath) //nolint:gosec // path validated by DownloadFile's safeJoin + Clean
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	return f, nil
}

// Write writes a file into the files directory of the managed device that
// backs this namespace, falling back to the default files directory when no
// device is present. Resolving the same way Stat and Open do keeps a written
// file findable by a subsequent read (#1538).
//
// The bytes stream into a temp file beside the destination and are renamed
// into place: writing straight to the real name put a growing, half-written
// file in every listing for the length of an upload (#1828).
func (v *StorageServiceVFS) Write(_ context.Context, path string, r io.Reader, opts WriteOptions) error {
	safePath, err := v.writePath(path)
	if err != nil {
		return err
	}
	if opts.IfNoneMatch == "*" {
		if _, statErr := os.Stat(safePath); statErr == nil {
			return ErrConflict
		}
	}
	return writeAtomic(safePath, r)
}

// MoveFileIn places the host file at srcAbs at path, renaming it rather than
// copying it when it can. See [FileMover].
func (v *StorageServiceVFS) MoveFileIn(ctx context.Context, srcAbs string, path string, opts WriteOptions) error {
	safePath, err := v.writePath(path)
	if err != nil {
		return err
	}
	return moveFileIn(srcAbs, safePath, opts, func(r io.Reader) error {
		return v.Write(ctx, path, r, opts)
	})
}

// writePath resolves a namespace path to the host path Write and MoveFileIn
// put it at.
func (v *StorageServiceVFS) writePath(path string) (string, error) {
	filesDir, err := v.filesDir()
	if err != nil {
		return "", err
	}
	// filepath.Clean before SafeJoin so static analyzers (CodeQL go/path-injection)
	// can follow the traversal guard rather than seeing tainted data reach the disk.
	safePath, err := storageutil.SafeJoin(filesDir, filepath.Clean(path))
	if err != nil {
		return "", ErrPermissionDenied
	}
	return filepath.Clean(safePath), nil
}

// Delete removes one or more files via the StorageService.
func (v *StorageServiceVFS) Delete(_ context.Context, path string, _ DeleteOptions) error {
	_, err := v.svc.DeleteFiles(storageutil.DeleteFilesParams{
		FilePaths: []string{path},
	})
	return err
}

// MkdirAll creates a directory (and parents) in the vault.
func (v *StorageServiceVFS) MkdirAll(_ context.Context, path string) error {
	dir, name := filepath.Split(strings.TrimRight(path, "/"))
	_, err := v.svc.CreateFolder(storageutil.CreateFolderParams{
		FolderDir:  dir,
		FolderName: name,
	})
	return err
}

// Move renames src to dst via the StorageService.
func (v *StorageServiceVFS) Move(_ context.Context, src, dst string) error {
	_, err := v.svc.MoveFile(storageutil.MoveFileParams{
		OldFilePath: src,
		NewFilePath: dst,
	})
	return err
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
		Path:      filepath.ToSlash(filepath.Join(dirPath, relPath)),
		Size:      f.Size(),
		IsDir:     f.IsDir(),
		MimeType:  mimeType,
		ModTime:   f.ModTime(),
		Namespace: nsID,
	}
}
