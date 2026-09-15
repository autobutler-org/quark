package storageutil

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	kzip "github.com/klauspost/compress/zip"
	"github.com/mholt/archiver/v4"
)

// ArchiveEntry represents a single entry visible at a given level inside an archive.
type ArchiveEntry struct {
	Name           string
	Size           int64
	CompressedSize int64
	IsDir          bool
	ModTime        time.Time
}

// ListArchiveParams contains parameters for listing archive contents.
type ListArchiveParams struct {
	// FilePath is the path to the archive, relative to the device files directory.
	FilePath string
	// SubPath is the virtual subdirectory inside the archive to list (empty = root).
	// Use forward slashes. Must not contain ".." or start with "/".
	SubPath string
	// DeviceSerial identifies the device. Empty string means the internal device.
	DeviceSerial string
}

// ListArchiveEntries returns the direct children of SubPath inside the archive
// at FilePath. Only archive headers are read — no entry data is decompressed.
func (s *StorageService) ListArchiveEntries(params ListArchiveParams) ([]ArchiveEntry, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}
	return ListArchiveEntriesImpl(params, device, defaultFilesDir)
}

// ListArchiveEntriesImpl is the testable entry point with injected device/filesDir.
func ListArchiveEntriesImpl(params ListArchiveParams, device *ManagedDevice, defaultFilesDir string) ([]ArchiveEntry, error) {
	filesDir := defaultFilesDir
	if device != nil {
		filesDir = device.FilesDir
	}

	fullPath, err := safeJoin(filesDir, params.FilePath)
	if err != nil {
		return nil, fmt.Errorf("file not found: %s", params.FilePath)
	}
	if _, err := os.Stat(fullPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("file not found: %s", params.FilePath)
	}

	fileType := DetermineFileTypeFromPath(fullPath)
	if fileType != FileTypeArchive {
		return nil, fmt.Errorf("file is not an archive: %s", params.FilePath)
	}

	ext := archiveExt(fullPath)
	if _, ok := supportedExts[ext]; !ok {
		return nil, fmt.Errorf("unsupported archive format %q", ext)
	}

	// Normalize the requested subpath: no leading/trailing slash, forward slashes only.
	subPath := normalizeSubPath(params.SubPath)
	if strings.Contains(subPath, "..") {
		return nil, fmt.Errorf("invalid subPath: %q", params.SubPath)
	}

	return listArchiveEntries(fullPath, subPath)
}

// listArchiveEntries opens the archive and collects the direct children of subPath.
// It reads only entry headers — no decompression of entry content occurs.
func listArchiveEntries(fullPath, subPath string) ([]ArchiveEntry, error) {
	f, err := os.Open(fullPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open archive: %w", err)
	}
	defer f.Close()

	format, input, err := archiver.Identify(context.Background(), filepath.Base(fullPath), f)
	if err != nil {
		return nil, fmt.Errorf("failed to identify archive format: %w", err)
	}

	ex, ok := format.(archiver.Extractor)
	if !ok {
		// Bare compression (e.g. plain .gz) — no directory structure.
		// Return a single synthetic entry representing the decompressed file.
		return listBareCompression(fullPath), nil
	}

	// Use a map keyed by name so we deduplicate and collect synthetic dirs in one pass.
	seen := make(map[string]*ArchiveEntry)
	prefix := ""
	if subPath != "" {
		prefix = subPath + "/"
	}

	var count int
	err = ex.Extract(context.Background(), input, func(_ context.Context, af archiver.FileInfo) error {
		count++
		if count > MaxArchiveEntries {
			return fmt.Errorf("archive exceeds maximum of %d entries", MaxArchiveEntries)
		}

		name := normalizeSubPath(af.NameInArchive)
		if name == "" || name == subPath {
			return nil
		}

		// Only include entries under the requested prefix.
		if !strings.HasPrefix(name, prefix) {
			return nil
		}

		// Trim the prefix to get the relative name.
		rel := strings.TrimPrefix(name, prefix)
		if rel == "" {
			return nil
		}

		// Extract the first path component — direct child.
		slash := strings.Index(rel, "/")
		childName := rel
		isDir := af.IsDir()
		if slash >= 0 {
			// Entry is deeper than one level — the intermediate dir is a synthetic entry.
			childName = rel[:slash]
			isDir = true
		}

		if _, exists := seen[childName]; !exists {
			entry := &ArchiveEntry{
				Name:    childName,
				IsDir:   isDir,
				ModTime: af.ModTime(),
			}
			if slash < 0 {
				entry.Size = af.Size()
				if zh, ok := af.Header.(kzip.FileHeader); ok {
					entry.CompressedSize = int64(zh.CompressedSize64)
				}
			}
			seen[childName] = entry
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	entries := make([]ArchiveEntry, 0, len(seen))
	for _, e := range seen {
		entries = append(entries, *e)
	}
	// Dirs first, then files; alphabetical within each group.
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir != entries[j].IsDir {
			return entries[i].IsDir
		}
		return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
	})
	return entries, nil
}

// listBareCompression returns a synthetic single-file listing for bare
// compression formats (e.g. plain .gz that doesn't wrap a tar).
func listBareCompression(fullPath string) []ArchiveEntry {
	ext := archiveExt(fullPath)
	base := filepath.Base(fullPath)
	stem := strings.TrimSuffix(base, ext)
	stem = strings.TrimSuffix(stem, ".tar")
	info, err := os.Stat(fullPath)
	var size int64
	if err == nil {
		size = info.Size() // approximate — real size is unknown until decompressed
	}
	return []ArchiveEntry{{Name: stem, Size: size, IsDir: false}}
}

// normalizeSubPath cleans a subpath to forward-slash, no leading/trailing slash.
func normalizeSubPath(p string) string {
	p = filepath.ToSlash(filepath.Clean(p))
	p = strings.Trim(p, "/")
	if p == "." {
		return ""
	}
	return p
}
