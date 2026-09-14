package storageutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/mholt/archiver/v4"
)

// ReadArchiveEntryParams contains parameters for reading a single file from an archive.
type ReadArchiveEntryParams struct {
	ArchivePath  string
	EntryPath    string
	DeviceSerial string
}

// ReadArchiveEntry opens an archive and returns a reader for the specified entry.
// The caller is responsible for closing the returned reader.
// Returns (reader, size, error). Size may be -1 if unknown.
func (s *StorageService) ReadArchiveEntry(params ReadArchiveEntryParams) (io.ReadCloser, int64, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, 0, err // coverage: ignore
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get files directory: %w", err)
	}
	return ReadArchiveEntryImpl(params, device, defaultFilesDir)
}

// ReadArchiveEntryImpl is the testable entry point with injected device/filesDir.
func ReadArchiveEntryImpl(params ReadArchiveEntryParams, device *ManagedDevice, defaultFilesDir string) (io.ReadCloser, int64, error) {
	filesDir := defaultFilesDir
	if device != nil {
		filesDir = device.FilesDir
	}

	// Not-found errors wrap os.ErrNotExist so a caller can tell them from a
	// broken archive. A path that escapes the files directory reads as not
	// found too.
	fullPath, err := safeJoin(filesDir, params.ArchivePath)
	if err != nil {
		return nil, 0, fmt.Errorf("file not found: %s: %w", params.ArchivePath, os.ErrNotExist)
	}
	if _, err := os.Stat(fullPath); IsNotExist(err) {
		return nil, 0, fmt.Errorf("file not found: %s: %w", params.ArchivePath, os.ErrNotExist)
	}

	entryPath := normalizeSubPath(params.EntryPath)
	if entryPath == "" || strings.Contains(entryPath, "..") {
		return nil, 0, fmt.Errorf("invalid entryPath: %q", params.EntryPath)
	}

	f, err := os.Open(fullPath)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to open archive: %w", err)
	}

	format, input, err := archiver.Identify(context.Background(), filepath.Base(fullPath), f)
	if err != nil {
		f.Close()
		return nil, 0, fmt.Errorf("failed to identify archive format: %w", err)
	}

	ex, ok := format.(archiver.Extractor)
	if !ok {
		f.Close()
		return nil, 0, fmt.Errorf("archive format %T does not support extraction", format)
	}

	// We need to find the matching entry. archiver.Extractor walks all entries
	// via a callback. We'll capture the matching entry's reader.
	type result struct {
		reader io.ReadCloser
		size   int64
	}

	var found *result
	err = ex.Extract(context.Background(), input, func(_ context.Context, af archiver.FileInfo) error {
		name := normalizeSubPath(af.NameInArchive)
		if name != entryPath {
			return nil
		}
		if af.IsDir() {
			return fmt.Errorf("entry %q is a directory", entryPath)
		}

		rc, openErr := af.Open()
		if openErr != nil {
			return openErr
		}
		found = &result{reader: rc, size: af.Size()}
		// Return a sentinel to stop iteration.
		return errEntryFound
	})

	if err != nil && !errors.Is(err, errEntryFound) {
		f.Close()
		return nil, 0, err
	}

	if found == nil {
		f.Close()
		return nil, 0, fmt.Errorf("entry not found in archive: %s: %w", entryPath, os.ErrNotExist)
	}

	// Wrap the reader to close the archive file when the entry reader is closed.
	return &archiveEntryReader{ReadCloser: found.reader, archive: f}, found.size, nil
}

var errEntryFound = errors.New("entry found")

// archiveEntryReader wraps an entry reader and closes the underlying archive
// file when the entry reader is closed.
type archiveEntryReader struct {
	io.ReadCloser
	archive *os.File
}

func (r *archiveEntryReader) Close() error {
	err1 := r.ReadCloser.Close()
	err2 := r.archive.Close()
	if err1 != nil {
		return err1
	}
	return err2
}
