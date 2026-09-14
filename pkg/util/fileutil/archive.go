package fileutil

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ListArchiveParams lists one level inside an archive. Nothing is extracted to
// disk: the storage path reads entry headers only, and the VFS path has to
// read the archive itself because a namespace has no OS path to hand a tool.
type ListArchiveParams struct {
	// Ctx bounds the VFS read.
	Ctx context.Context
	// Registry serves the listing when no serial routes past it.
	Registry vfs.Registry
	// Storage reads the archive for a device-scoped request.
	Storage *storageutil.StorageService
	// FilePath is the archive, relative to the device files directory.
	FilePath string
	// SubPath is the virtual directory inside the archive, empty for its root.
	SubPath string
	// Serial identifies the device, empty for the internal one.
	Serial string
}

// ListArchiveResult is the direct children of the requested level.
type ListArchiveResult struct {
	Entries []FileNode
}

// ListArchive returns the direct children of SubPath inside the archive at
// FilePath, as virtual paths the client passes back to list deeper.
func ListArchive(params ListArchiveParams) (ListArchiveResult, error) {
	// VFS path: only when no serial is provided.
	if params.Serial == "" {
		if fsys := FilesVFS(params.Registry); fsys != nil {
			return listArchiveVFS(params, fsys)
		}
	}

	// StorageService fallback.
	entries, err := params.Storage.ListArchiveEntries(storageutil.ListArchiveParams{
		FilePath:     params.FilePath,
		SubPath:      params.SubPath,
		DeviceSerial: params.Serial,
	})
	if err != nil {
		return ListArchiveResult{}, err
	}

	result := make([]FileNode, len(entries))
	for i, e := range entries {
		// Construct a virtual dirPath: filePath/subPath/name
		// This is the path the client must pass back as filePath to list deeper.
		virtualPath := params.FilePath
		if params.SubPath != "" {
			virtualPath = filepath.ToSlash(filepath.Join(virtualPath, params.SubPath))
		}
		dirPath := filepath.ToSlash(filepath.Join(virtualPath, e.Name))

		fileType := ""
		if !e.IsDir {
			fileType = string(storageutil.DetermineFileTypeFromPath(e.Name))
		}

		// Strip any archive extension segments from the path for display
		// but preserve the full virtual path for navigation.
		nameParts := strings.Split(e.Name, "/")
		displayName := nameParts[len(nameParts)-1]

		result[i] = FileNode{
			Name:           displayName,
			Size:           e.Size,
			CompressedSize: e.CompressedSize,
			IsDir:          e.IsDir,
			DeviceName:     "",
			DevicePath:     "",
			DirPath:        dirPath,
			FullPath:       dirPath,
			DeviceSerial:   params.Serial,
			FileType:       fileType,
		}
	}

	return ListArchiveResult{Entries: result}, nil
}

// listArchiveVFS lists an archive read out of the VFS namespace.
func listArchiveVFS(params ListArchiveParams, fsys vfs.VFS) (ListArchiveResult, error) {
	zr, archive, err := readZipVFS(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return ListArchiveResult{}, err
	}
	defer archive.Close()

	// Normalize subPath (no leading/trailing slash).
	normalizedSub := strings.Trim(filepath.ToSlash(params.SubPath), "/")
	prefix := ""
	if normalizedSub != "" {
		prefix = normalizedSub + "/"
	}

	seen := make(map[string]struct{})
	var result []FileNode

	for _, f := range zr.File {
		name := filepath.ToSlash(f.Name)
		name = strings.Trim(name, "/")
		if name == "" || name == normalizedSub {
			continue
		}
		if !strings.HasPrefix(name, prefix) {
			continue
		}

		rel := strings.TrimPrefix(name, prefix)
		if rel == "" {
			continue
		}

		// Only the direct child (first path component).
		before, _, hasChildren := strings.Cut(rel, "/")
		childName := rel
		isDir := f.FileInfo().IsDir()
		var size int64
		var compressedSize int64
		if hasChildren {
			childName = before
			isDir = true
		} else {
			size = int64(f.UncompressedSize64)
			compressedSize = int64(f.CompressedSize64)
		}

		if _, exists := seen[childName]; exists {
			continue
		}
		seen[childName] = struct{}{}

		// Construct the virtual path for client navigation.
		virtualPath := params.FilePath
		if normalizedSub != "" {
			virtualPath = filepath.ToSlash(filepath.Join(virtualPath, normalizedSub))
		}
		dirPath := filepath.ToSlash(filepath.Join(virtualPath, childName))

		fileType := ""
		if !isDir {
			fileType = string(storageutil.DetermineFileTypeFromPath(childName))
		}

		result = append(result, FileNode{
			Name:           childName,
			Size:           size,
			CompressedSize: compressedSize,
			IsDir:          isDir,
			DeviceName:     "",
			DevicePath:     "",
			DirPath:        dirPath,
			FullPath:       dirPath,
			DeviceSerial:   params.Serial,
			FileType:       fileType,
		})
	}

	if result == nil {
		result = []FileNode{}
	}
	return ListArchiveResult{Entries: result}, nil
}

// OpenArchiveEntryParams reads one entry out of an archive without extracting
// anything to disk.
type OpenArchiveEntryParams struct {
	// Ctx bounds the VFS read.
	Ctx context.Context
	// Registry serves the read when no serial routes past it.
	Registry vfs.Registry
	// Storage reads the archive for a device-scoped request.
	Storage *storageutil.StorageService
	// ArchivePath is the archive, relative to the device files directory.
	ArchivePath string
	// EntryPath is the entry inside the archive.
	EntryPath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// WantsJPEG asks for an image entry to come back as JPEG.
	WantsJPEG bool
}

// OpenArchiveEntryResult is the entry's stream. The caller closes the reader.
type OpenArchiveEntryResult struct {
	// Reader streams the decompressed entry.
	Reader io.ReadCloser
	// Size is the entry's length, negative when the archive does not say.
	Size int64
	// Kind is DownloadJPEG when the entry has to be converted, otherwise
	// DownloadContents.
	Kind DownloadKind
	// FileName is the name the client is offered in Content-Disposition.
	FileName string
	// ContentType is the type to serve.
	ContentType string
}

// OpenArchiveEntry opens a single entry inside an archive for streaming, and
// says whether it has to be converted to JPEG on the way out.
func OpenArchiveEntry(params OpenArchiveEntryParams) (OpenArchiveEntryResult, error) {
	entry, err := openArchiveEntryStream(params)
	if err != nil {
		return OpenArchiveEntryResult{}, err
	}

	// RAW previews come from an external tool that needs an OS path, and an
	// entry is only a stream, so RAW entries are served as they are (#1851).
	if params.WantsJPEG &&
		storageutil.DetermineFileTypeFromPath(params.EntryPath) == storageutil.FileTypeImage &&
		!photoutil.IsRawFile(params.EntryPath) {
		entry.Kind = DownloadJPEG
		entry.FileName = JPEGFileName(params.EntryPath)
		entry.ContentType = "image/jpeg"
		return entry, nil
	}

	entry.Kind = DownloadContents
	entry.FileName = filepath.Base(params.EntryPath)
	entry.ContentType = "application/octet-stream"
	return entry, nil
}

// FindArchiveParams asks whether a files path names an entry inside an archive.
type FindArchiveParams struct {
	// Ctx bounds the VFS stat.
	Ctx context.Context
	// Registry serves the stat when no serial routes past it.
	Registry vfs.Registry
	// Storage resolves the path for a device-scoped request.
	Storage *storageutil.StorageService
	// FilePath is the requested path, relative to the device files directory.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
}

// FindArchiveResult is the archive and entry a files path names.
type FindArchiveResult struct {
	// Found is false when no folder segment of the path is an archive file.
	Found bool
	// ArchivePath is the archive, relative to the device files directory.
	ArchivePath string
	// EntryPath is the entry inside the archive.
	EntryPath string
	// ModTime is the archive's modification time.
	ModTime time.Time
}

// FindArchive reports whether a files path names an entry inside an archive:
// "a/photos.zip/pics/red.png" is the entry "pics/red.png" of "a/photos.zip"
// when that is a file. A folder only named like an archive does not count, nor
// does a path that does not exist. The archive is stat-ed rather than opened,
// so a cache keyed on its modification time stays cheap to check.
func FindArchive(params FindArchiveParams) (FindArchiveResult, error) {
	segments := strings.Split(strings.Trim(filepath.ToSlash(params.FilePath), "/"), "/")
	for i, segment := range segments[:len(segments)-1] {
		// path.Ext of "x.tar.gz" is ".gz", which is in the set as well.
		if !slices.Contains(storageutil.SupportedArchiveExts(), strings.ToLower(path.Ext(segment))) {
			continue
		}
		archivePath := strings.Join(segments[:i+1], "/")
		info, err := statFilesPath(params, archivePath)
		if err != nil || info == nil {
			return FindArchiveResult{}, err
		}
		if info.IsDir {
			continue
		}
		return FindArchiveResult{
			Found:       true,
			ArchivePath: archivePath,
			EntryPath:   strings.Join(segments[i+1:], "/"),
			ModTime:     info.ModTime,
		}, nil
	}
	return FindArchiveResult{}, nil
}

// statFilesPath stats a files path the way OpenArchiveEntry reads it: through
// the VFS when no serial routes past it, otherwise through the StorageService.
// A path that does not resolve is nil with no error; the caller's own lookup
// of the full path reports it.
func statFilesPath(params FindArchiveParams, filePath string) (*vfs.FileInfo, error) {
	if params.Serial == "" {
		if fsys := FilesVFS(params.Registry); fsys != nil {
			info, err := fsys.Stat(params.Ctx, filePath)
			if errors.Is(err, vfs.ErrNotFound) || storageutil.IsNotExist(err) {
				return nil, nil
			}
			if err != nil {
				return nil, fmt.Errorf("failed to stat %s: %w", filePath, err)
			}
			return &info, nil
		}
	}

	resolved, err := params.Storage.DownloadFile(storageutil.DownloadFileParams{
		FilePath:     filePath,
		DeviceSerial: params.Serial,
	})
	if err != nil {
		return nil, nil
	}
	info, err := os.Stat(resolved.FullPath)
	if storageutil.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to stat %s: %w", filePath, err)
	}
	return &vfs.FileInfo{IsDir: info.IsDir(), ModTime: info.ModTime()}, nil
}

// openArchiveEntryStream finds an entry and opens its decompressed stream.
func openArchiveEntryStream(params OpenArchiveEntryParams) (OpenArchiveEntryResult, error) {
	// VFS path: only when no serial is provided.
	if params.Serial == "" {
		if fsys := FilesVFS(params.Registry); fsys != nil {
			return openArchiveEntryVFS(params, fsys)
		}
	}

	// StorageService fallback.
	reader, size, err := params.Storage.ReadArchiveEntry(storageutil.ReadArchiveEntryParams{
		ArchivePath:  params.ArchivePath,
		EntryPath:    params.EntryPath,
		DeviceSerial: params.Serial,
	})
	if err != nil {
		log.Printf("[files] ReadArchiveEntry failed: path=%q entry=%q err=%v", params.ArchivePath, params.EntryPath, err)
		if errors.Is(err, fs.ErrNotExist) {
			return OpenArchiveEntryResult{}, notFound(err)
		}
		return OpenArchiveEntryResult{}, err
	}
	return OpenArchiveEntryResult{Reader: reader, Size: size}, nil
}

// openArchiveEntryVFS finds an entry in an archive read out of the VFS namespace.
func openArchiveEntryVFS(params OpenArchiveEntryParams, fsys vfs.VFS) (OpenArchiveEntryResult, error) {
	zr, archive, err := readZipVFS(params.Ctx, fsys, params.ArchivePath)
	if err != nil {
		return OpenArchiveEntryResult{}, err
	}

	// Normalize the requested entry path (forward slashes, no leading slash).
	normalizedEntry := strings.Trim(filepath.ToSlash(params.EntryPath), "/")

	for _, f := range zr.File {
		name := strings.Trim(filepath.ToSlash(f.Name), "/")
		if name != normalizedEntry {
			continue
		}

		rc, err := openZipEntry(f)
		if err != nil {
			archive.Close()
			return OpenArchiveEntryResult{}, err
		}
		// The entry streams out of the archive, so the archive closes with it.
		return OpenArchiveEntryResult{
			Reader: entryReader{ReadCloser: rc, archive: archive},
			Size:   int64(f.UncompressedSize64),
		}, nil
	}

	archive.Close()
	return OpenArchiveEntryResult{}, notFoundf("entry %q not found in archive", params.EntryPath)
}

// readZipVFS opens an archive in the VFS namespace for random access, which is
// what a zip reader needs. The namespaces that hand back an *os.File (local
// disk, storage service) supply that directly; only a namespace whose Open is a
// plain stream has to be buffered. Buffering unconditionally is what turned a
// 4 GiB archive into a 500 — io.ReadAll wanted ~12 GiB of heap to hold it
// (#1705). The returned Closer owns the archive and must outlive every entry
// reader taken from it.
func readZipVFS(ctx context.Context, fsys vfs.VFS, filePath string) (*zip.Reader, io.Closer, error) {
	r, err := fsys.Open(ctx, filePath)
	if err != nil {
		return nil, nil, notFound(err)
	}

	if ra, ok := r.(io.ReaderAt); ok {
		if info, statErr := fsys.Stat(ctx, filePath); statErr == nil && info.Size > 0 {
			zr, err := zip.NewReader(ra, info.Size)
			if err != nil {
				r.Close()
				return nil, nil, fmt.Errorf("failed to open zip archive: %w", err)
			}
			return zr, r, nil
		}
	}

	defer r.Close()

	data, err := io.ReadAll(r)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to read archive: %w", err)
	}

	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, nil, fmt.Errorf("failed to open zip archive: %w", err)
	}
	return zr, nopCloser{}, nil
}

// nopCloser closes the buffered archive that has nothing to close.
type nopCloser struct{}

func (nopCloser) Close() error { return nil }

// entryReader keeps the archive open behind a streaming entry and closes it
// with the entry.
type entryReader struct {
	io.ReadCloser
	archive io.Closer
}

func (e entryReader) Close() error {
	err := e.ReadCloser.Close()
	if cerr := e.archive.Close(); err == nil {
		err = cerr
	}
	return err
}

// ExtractZipVFS extracts a .zip archive via the VFS layer, streaming each entry
// out of the archive and back through VFS.Write / VFS.MkdirAll.
func ExtractZipVFS(ctx context.Context, fsys vfs.VFS, filePath string) error {
	zr, archive, err := readZipVFS(ctx, fsys, filePath)
	if err != nil {
		return err
	}
	defer archive.Close()

	// Determine the destination directory: sibling dir named after the archive stem.
	base := filepath.Base(filePath)
	stem := strings.TrimSuffix(base, filepath.Ext(base))
	destDir := path.Join(path.Dir(filePath), stem)

	if err := fsys.MkdirAll(ctx, destDir); err != nil {
		return fmt.Errorf("failed to create destination directory: %w", err)
	}

	// Canonical Zip Slip anchor: every resolved path must begin with this prefix.
	cleanDestDir := path.Clean(destDir) + "/"

	var entryCount int
	for _, f := range zr.File {
		// Extracting a multi-gigabyte archive takes minutes; stop writing when
		// the caller has gone away rather than finishing the whole thing.
		if err := ctx.Err(); err != nil {
			return err
		}

		entryCount++
		if entryCount > storageutil.MaxArchiveEntries {
			return fmt.Errorf("archive exceeds maximum of %d entries", storageutil.MaxArchiveEntries)
		}

		// Normalize to forward-slash, clean, and strip any leading slash.
		entryName := strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(f.Name)), "/")
		if entryName == "" || entryName == "." {
			continue
		}

		destPath := path.Join(destDir, entryName)

		// Zip Slip guard: the resolved destination must stay within destDir.
		// This is the canonical check CodeQL and other scanners understand.
		if !strings.HasPrefix(path.Clean(destPath)+"/", cleanDestDir) {
			continue // path traversal attempt — discard silently
		}

		if f.FileInfo().IsDir() {
			if err := fsys.MkdirAll(ctx, destPath); err != nil {
				return fmt.Errorf("failed to create directory %s: %w", destPath, err)
			}
			continue
		}

		// Ensure parent directory exists.
		parentDir := path.Dir(destPath)
		if err := fsys.MkdirAll(ctx, parentDir); err != nil {
			return fmt.Errorf("failed to create parent directory for %s: %w", destPath, err)
		}

		rc, err := openZipEntry(f)
		if err != nil {
			return err
		}

		// Apply per-entry size limit. The declared size rejects an honest
		// oversized entry outright; the LimitReader caps a lying header. Reading
		// one byte past the limit and never checking it, as this used to, wrote
		// the entry silently truncated instead of refusing it.
		if f.UncompressedSize64 > uint64(storageutil.MaxArchiveEntryBytes) {
			rc.Close()
			return fmt.Errorf("archive entry %s exceeds maximum allowed size of %d bytes", f.Name, storageutil.MaxArchiveEntryBytes)
		}
		limited := io.LimitReader(rc, storageutil.MaxArchiveEntryBytes)
		if err := fsys.Write(ctx, destPath, limited, vfs.WriteOptions{}); err != nil {
			rc.Close()
			return fmt.Errorf("failed to write %s: %w", destPath, err)
		}
		rc.Close()
	}

	return nil
}
