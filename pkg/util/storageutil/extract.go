package storageutil

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync/atomic"

	"github.com/mholt/archiver/v4"
)

const (
	// MaxArchiveEntryBytes is the maximum number of bytes written per entry.
	// Guards against decompression bombs without rejecting legitimate large files.
	MaxArchiveEntryBytes int64 = 10 * 1024 * 1024 * 1024 // 10 GiB
)

// MaxArchiveEntries is the maximum number of entries extracted from a single
// archive. Declared as a var so tests can override it without building 100k
// files.
var MaxArchiveEntries = 100_000

// supportedExts is the set of archive extensions we accept for extraction.
// To add a new format: add its extension here. mholt/archiver handles the rest
// as long as the underlying Go library for that format is available.
var supportedExts = map[string]struct{}{
	".zip":    {},
	".rar":    {},
	".tar":    {},
	".tar.gz": {},
	".tgz":    {},
	".gz":     {},
	".7z":     {},
}

// ExtractFileParams contains parameters for extracting an archive file.
type ExtractFileParams struct {
	FilePath     string
	DeviceSerial string
}

// ExtractFileResult contains the result of an extraction operation.
type ExtractFileResult struct {
	DestDir string
	// CreatedPath is the new top-level item, files-relative: the folder an
	// archive was extracted into, or the file a bare compressed stream was
	// decompressed to. Both are given names nothing else has, so it is always
	// new.
	CreatedPath string
}

// SupportedArchiveExts returns the sorted list of archive extensions that can
// be extracted. Useful for UI hints and validation.
func SupportedArchiveExts() []string {
	exts := make([]string, 0, len(supportedExts))
	for ext := range supportedExts {
		exts = append(exts, ext)
	}
	sort.Strings(exts)
	return exts
}

// ExtractFile extracts an archive in place on disk.
// The archive format is inferred from the file extension via mholt/archiver.
func (s *StorageService) ExtractFile(params ExtractFileParams) (*ExtractFileResult, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}
	return ExtractFileImpl(params, device, defaultFilesDir)
}

// ExtractFileImpl extracts an archive using a pre-resolved device and files
// directory. Use this in tests to inject test devices without hitting the real
// filesystem detector.
func ExtractFileImpl(params ExtractFileParams, device *ManagedDevice, defaultFilesDir string) (*ExtractFileResult, error) {
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
		return nil, fmt.Errorf("unsupported archive format %q: supported formats are %s",
			ext, strings.Join(SupportedArchiveExts(), ", "))
	}

	result, err := extractArchive(fullPath)
	if err != nil {
		return nil, err
	}
	// The extractors know the absolute path they created; callers address
	// files relative to the files directory.
	if rel, relErr := filepath.Rel(filepath.Clean(filesDir), result.CreatedPath); relErr == nil {
		result.CreatedPath = filepath.ToSlash(rel)
	}
	return result, nil
}

// extractArchive opens the archive at fullPath, identifies its format via
// mholt/archiver, and extracts all entries into a new sibling directory.
func extractArchive(fullPath string) (*ExtractFileResult, error) {
	f, err := os.Open(fullPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open archive: %w", err)
	}
	defer f.Close()

	format, input, err := archiver.Identify(context.Background(), filepath.Base(fullPath), f)
	if err != nil {
		return nil, fmt.Errorf("failed to identify archive format: %w", err)
	}

	// Bare compression formats (e.g. .gz not wrapping a .tar) implement
	// Decompressor rather than Extractor. They decompress to a single file.
	if decomp, ok := format.(archiver.Decompressor); ok {
		if _, isArchive := format.(archiver.Extractor); !isArchive {
			return extractDecompressed(decomp, input, fullPath)
		}
	}

	ex, ok := format.(archiver.Extractor)
	if !ok {
		return nil, fmt.Errorf("archive format %T does not support extraction", format)
	}

	destDir := archiveDestDir(fullPath)
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create destination directory: %w", err) // coverage: ignore
	}

	var entryCount atomic.Int64
	err = ex.Extract(context.Background(), input, func(_ context.Context, af archiver.FileInfo) error {
		n := entryCount.Add(1)
		if n > int64(MaxArchiveEntries) {
			return fmt.Errorf("archive exceeds maximum of %d entries", MaxArchiveEntries)
		}
		return extractArchiveEntry(af, destDir)
	})
	if err != nil {
		return nil, err
	}

	return &ExtractFileResult{DestDir: destDir, CreatedPath: destDir}, nil
}

// extractDecompressed handles bare compression formats (e.g. bare .gz not
// wrapping a .tar). It decompresses the stream to a single file in the same
// directory as the archive, named after the archive stem.
func extractDecompressed(decomp archiver.Decompressor, r io.Reader, fullPath string) (*ExtractFileResult, error) {
	rc, err := decomp.OpenReader(r)
	if err != nil {
		return nil, fmt.Errorf("failed to decompress: %w", err)
	}
	defer rc.Close()

	stem := strings.TrimSuffix(filepath.Base(fullPath), archiveExt(fullPath))
	// Also strip a trailing .tar if present (e.g. foo.tar.gz → foo).
	stem = strings.TrimSuffix(stem, ".tar")
	outPath := GetNonConflictingPath(filepath.Join(filepath.Dir(fullPath), stem))

	out, err := os.Create(outPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create output file: %w", err) // coverage: ignore
	}
	defer out.Close()

	limited := io.LimitReader(rc, MaxArchiveEntryBytes+1)
	n, err := io.Copy(out, limited)
	if err != nil {
		return nil, fmt.Errorf("failed to write decompressed output: %w", err)
	}
	if n > MaxArchiveEntryBytes {
		return nil, fmt.Errorf("decompressed output exceeds maximum allowed size of %d bytes", MaxArchiveEntryBytes)
	}

	return &ExtractFileResult{DestDir: filepath.Dir(outPath), CreatedPath: outPath}, nil
}

// extractArchiveEntry writes a single archiver.FileInfo into destDir, applying
// path traversal guards and a per-entry size cap.
func extractArchiveEntry(af archiver.FileInfo, destDir string) error {
	name := af.NameInArchive

	cleaned := filepath.Clean(name)
	if strings.HasPrefix(cleaned, "..") || filepath.IsAbs(cleaned) {
		return fmt.Errorf("invalid archive entry path: %s", name)
	}

	targetPath := filepath.Join(destDir, cleaned)

	// Double-guard: ensure the resolved path is still within destDir.
	absDestDir, err := filepath.Abs(destDir)
	if err != nil {
		return fmt.Errorf("failed to resolve destination directory: %w", err) // coverage: ignore
	}
	absTarget, err := filepath.Abs(targetPath)
	if err != nil {
		return fmt.Errorf("failed to resolve target path: %w", err) // coverage: ignore
	}
	if !strings.HasPrefix(absTarget, absDestDir+string(os.PathSeparator)) && absTarget != absDestDir {
		return fmt.Errorf("archive entry %q escapes destination directory", name)
	}

	if af.IsDir() {
		if err := os.MkdirAll(targetPath, 0755); err != nil {
			return fmt.Errorf("failed to create directory %s: %w", targetPath, err) // coverage: ignore
		}
		return nil
	}

	// Skip symlinks — they can escape the dest dir via relative targets.
	if af.LinkTarget != "" {
		return nil
	}

	if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
		return fmt.Errorf("failed to create parent directory for %s: %w", targetPath, err) // coverage: ignore
	}

	var rc fs.File
	if af.Open != nil {
		rc, err = af.Open()
		if err != nil {
			return fmt.Errorf("failed to open archive entry %s: %w", name, err)
		}
	} else {
		return fmt.Errorf("archive entry %s has no open function", name)
	}
	defer rc.Close()

	out, err := os.Create(targetPath)
	if err != nil {
		return fmt.Errorf("failed to create file %s: %w", targetPath, err) // coverage: ignore
	}
	defer out.Close()

	limited := io.LimitReader(rc, MaxArchiveEntryBytes+1)
	n, err := io.Copy(out, limited)
	if err != nil {
		return fmt.Errorf("failed to extract file %s: %w", name, err)
	}
	if n > MaxArchiveEntryBytes {
		return fmt.Errorf("archive entry %q exceeds maximum allowed size of %d bytes", name, MaxArchiveEntryBytes)
	}

	return nil
}

// archiveExt returns the canonical extension for an archive path, handling
// double-extensions like ".tar.gz".
func archiveExt(path string) string {
	lower := strings.ToLower(path)
	for _, ext := range []string{".tar.gz", ".tar.bz2", ".tar.xz"} {
		if strings.HasSuffix(lower, ext) {
			return ext
		}
	}
	if strings.HasSuffix(lower, ".tgz") {
		return ".tgz"
	}
	return strings.ToLower(filepath.Ext(path))
}

// archiveDestDir returns a conflict-safe destination directory for an archive,
// stripping double-extensions (e.g. "foo.tar.gz" → "foo", "foo.zip" → "foo").
func archiveDestDir(fullPath string) string {
	base := filepath.Base(fullPath)
	ext := archiveExt(fullPath)
	stem := strings.TrimSuffix(base, ext)
	// Strip a trailing .tar that may remain after stripping .gz/.bz2/.xz.
	stem = strings.TrimSuffix(stem, ".tar")
	dest := filepath.Join(filepath.Dir(fullPath), stem)
	return GetNonConflictingPath(dest)
}
