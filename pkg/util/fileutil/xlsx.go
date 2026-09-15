package fileutil

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// MaxBufferedXlsxBytes bounds the one namespace a workbook cannot be read from
// in place. A zip is read from its central directory backwards, so it needs
// random access; the namespaces that hand back an *os.File give that for free,
// and only a namespace whose Open is a plain stream has to be buffered. That
// case is bounded rather than trusted — buffering whatever arrives is what
// turned a 4 GiB archive into a 500 (#1705).
const MaxBufferedXlsxBytes = 64 << 20 // 64 MiB

// ConvertXlsxParams converts one .xlsx or .xlsm into the .qsheet the Sheets
// editor opens, written beside the workbook it came from.
type ConvertXlsxParams struct {
	// Ctx bounds the read and the write.
	Ctx context.Context
	// Registry reads and writes through the VFS when no serial routes past it.
	Registry vfs.Registry
	// Storage serves the request for a device-scoped path, or when there is
	// no VFS namespace to route to.
	Storage *storageutil.StorageService
	// EventBus is told about the file that appeared. Required, as it is for
	// every other mutation here.
	EventBus *eventbus.Bus
	// FilePath is the files-relative path of the workbook.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Overwrite lets the conversion replace a .qsheet that is already there.
	// Without it an existing file is reported as [vfs.ErrConflict] and left
	// alone, so a conversion never silently destroys earlier work.
	Overwrite bool
}

// ConvertXlsxResult reports the .qsheet that was written and what it holds.
type ConvertXlsxResult struct {
	// Path is where the new spreadsheet landed, files-relative.
	Path string
	// Replaced is true when an existing .qsheet was overwritten, so nothing
	// new was created.
	Replaced bool
	// Tabs, Rows and Cells are what the workbook came to.
	Tabs  int
	Rows  int
	Cells int
}

// ConvertXlsxToQsheet reads the workbook at params.FilePath and writes it back
// as a sibling .qsheet, the format the Sheets editor already understands
// (#1741). The original workbook is left untouched.
//
// The conversion streams: the workbook is read in place, and the .qsheet is
// piped into the destination as its rows are produced rather than assembled in
// memory first. It lands on a temporary name and is moved into place only once
// the whole workbook has converted, so a workbook that fails halfway leaves
// nothing behind — least of all a half-written file where the user's own
// spreadsheet used to be.
func ConvertXlsxToQsheet(params ConvertXlsxParams) (ConvertXlsxResult, error) {
	if !IsXlsxPath(params.FilePath) {
		return ConvertXlsxResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a spreadsheet Quark can convert: %s", filepath.Base(params.FilePath)),
		}
	}

	dir := path.Dir(cleanRelPath(params.FilePath))
	if dir == "." || dir == "/" {
		dir = ""
	}
	base := path.Base(cleanRelPath(params.FilePath))
	stem := strings.TrimSuffix(base, filepath.Ext(base))
	target := path.Join(dir, stem+".qsheet")

	exists, err := fileExists(params.Ctx, params.Registry, params.Storage, params.Serial, target)
	if err != nil {
		return ConvertXlsxResult{}, err
	}
	if exists && !params.Overwrite {
		return ConvertXlsxResult{}, fmt.Errorf("%w: %s already exists", vfs.ErrConflict, target)
	}

	source, size, closer, err := openXlsxSource(params)
	if err != nil {
		return ConvertXlsxResult{}, err
	}
	defer closer.Close()

	// The conversion writes onto a pipe the destination reads from, so the
	// .qsheet is never held whole on either side.
	dest := uploadutil.Destination{
		Registry: params.Registry,
		Storage:  params.Storage,
		// The event for the temporary file would announce a path that is about
		// to be renamed; the move below publishes the one that matters.
		EventBus: nil,
	}
	tempName := "." + stem + ".qsheet.converting"

	pr, pw := io.Pipe()
	converted := make(chan convertOutcome, 1)
	go func() {
		result, err := xlsxutil.ConvertToQsheet(xlsxutil.ConvertToQsheetParams{
			Source: source,
			Size:   size,
			Out:    pw,
		})
		// Closing with the error is what stops the destination from storing a
		// truncated document as if it were whole.
		pw.CloseWithError(err)
		converted <- convertOutcome{result: result, err: err}
	}()

	_, writeErr := dest.WriteFile(uploadutil.WriteFileParams{
		Ctx:       params.Ctx,
		Reader:    pr,
		RootDir:   dir,
		FileName:  tempName,
		Serial:    params.Serial,
		Overwrite: true,
	})
	// Unblocks the conversion if the destination gave up first.
	pr.CloseWithError(writeErr)
	outcome := <-converted

	tempPath := path.Join(dir, tempName)
	if outcome.err != nil {
		discardTemp(params, tempPath)
		return ConvertXlsxResult{}, convertError(outcome.err)
	}
	if writeErr != nil {
		discardTemp(params, tempPath)
		return ConvertXlsxResult{}, writeErr
	}

	if _, err := MoveFile(MoveFileParams{
		Ctx:             params.Ctx,
		Registry:        params.Registry,
		Storage:         params.Storage,
		EventBus:        params.EventBus,
		OldFilePath:     tempPath,
		NewFilePath:     target,
		OldDeviceSerial: params.Serial,
		NewDeviceSerial: params.Serial,
	}); err != nil {
		discardTemp(params, tempPath)
		return ConvertXlsxResult{}, err
	}

	return ConvertXlsxResult{
		Path:     target,
		Replaced: exists,
		Tabs:     outcome.result.Tabs,
		Rows:     outcome.result.Rows,
		Cells:    outcome.result.Cells,
	}, nil
}

// IsXlsxPath reports whether a path names a workbook this can convert. The
// legacy .xls is not one: it is a binary compound file rather than the OOXML
// package .xlsx and .xlsm share, and needs a different reader entirely.
func IsXlsxPath(filePath string) bool {
	switch strings.ToLower(filepath.Ext(filePath)) {
	case ".xlsx", ".xlsm":
		return true
	}
	return false
}

// convertOutcome carries what the conversion goroutine produced back to the
// caller, so a conversion failure is reported as itself rather than as the
// broken-pipe write error it causes.
type convertOutcome struct {
	result xlsxutil.ConvertToQsheetResult
	err    error
}

// convertError maps what xlsxutil reports onto the errors the handler already
// derives status codes from. A workbook that is malformed or past the
// conversion limits is the caller's file, not a server fault.
func convertError(err error) error {
	if errors.Is(err, xlsxutil.ErrNotSpreadsheet) || errors.Is(err, xlsxutil.ErrTooLarge) {
		return &UnsupportedError{Err: err}
	}
	return err
}

// cleanRelPath normalizes a files-relative path to the forward-slash form the
// VFS and the storage service both address files by.
func cleanRelPath(filePath string) string {
	return strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(filePath)), "/")
}

// fileExists reports whether something already occupies a files-relative path,
// asking the same source a write to that serial would go through.
func fileExists(ctx context.Context, registry vfs.Registry, storage *storageutil.StorageService, serial, filePath string) (bool, error) {
	if serial == "" {
		if fsys := FilesVFS(registry); fsys != nil {
			_, err := fsys.Stat(ctx, filePath)
			if err == nil {
				return true, nil
			}
			if errors.Is(err, vfs.ErrNotFound) || errors.Is(err, os.ErrNotExist) {
				return false, nil
			}
			return false, err
		}
	}
	if storage == nil {
		return false, ErrNoFilesNamespace
	}
	if _, err := storage.StatFile(storageutil.StatFileParams{
		FilePath:     filePath,
		DeviceSerial: serial,
	}); err != nil {
		// The storage service reports every stat failure the same way, and a
		// missing file is the one this asked about.
		return false, nil
	}
	return true, nil
}

// discardTemp removes the half-written conversion. It is best effort: the
// error that got us here is the one worth reporting, and a leftover temporary
// file is a smaller problem than losing it.
func discardTemp(params ConvertXlsxParams, tempPath string) {
	var err error
	if fsys := FilesVFS(params.Registry); params.Serial == "" && fsys != nil {
		err = fsys.Delete(params.Ctx, tempPath, vfs.DeleteOptions{})
	} else if params.Storage != nil {
		_, err = params.Storage.DeleteFiles(storageutil.DeleteFilesParams{
			RootDir:      path.Dir(tempPath),
			FilePaths:    []string{path.Base(tempPath)},
			DeviceSerial: params.Serial,
		})
	}
	if err != nil && !errors.Is(err, vfs.ErrNotFound) {
		slog.Warn("xlsx: could not remove the partial conversion", "path", tempPath, "err", err)
	}
}

// openXlsxSource opens the workbook for random access, which is what reading a
// zip needs: the central directory sits at the end of the file. The namespaces
// that hand back an *os.File satisfy that directly, so nothing is copied.
func openXlsxSource(params ConvertXlsxParams) (io.ReaderAt, int64, io.Closer, error) {
	if params.Serial == "" {
		if fsys := FilesVFS(params.Registry); fsys != nil {
			return openXlsxVFS(params.Ctx, fsys, params.FilePath)
		}
	}
	if params.Storage == nil {
		return nil, 0, nil, ErrNoFilesNamespace
	}

	opened, err := OpenDownload(OpenDownloadParams{
		Storage:  params.Storage,
		FilePath: params.FilePath,
		Serial:   params.Serial,
	})
	if err != nil {
		return nil, 0, nil, err
	}
	if opened.File == nil {
		return nil, 0, nil, &UnsupportedError{Err: fmt.Errorf("not a file: %s", params.FilePath)}
	}
	info, err := opened.File.Stat()
	if err != nil {
		opened.File.Close()
		return nil, 0, nil, err
	}
	return opened.File, info.Size(), opened.File, nil
}

// openXlsxVFS opens a workbook in the VFS namespace for random access, falling
// back to a bounded copy for a namespace whose Open is a plain stream.
func openXlsxVFS(ctx context.Context, fsys vfs.VFS, filePath string) (io.ReaderAt, int64, io.Closer, error) {
	r, err := fsys.Open(ctx, filePath)
	if err != nil {
		return nil, 0, nil, notFound(err)
	}

	if ra, ok := r.(io.ReaderAt); ok {
		if info, statErr := fsys.Stat(ctx, filePath); statErr == nil && info.Size > 0 {
			return ra, info.Size, r, nil
		}
	}

	defer r.Close()
	// Reading one byte past the limit is what tells an oversized workbook from
	// one that merely fills it.
	buf, err := io.ReadAll(io.LimitReader(r, MaxBufferedXlsxBytes+1))
	if err != nil {
		return nil, 0, nil, err
	}
	if int64(len(buf)) > MaxBufferedXlsxBytes {
		return nil, 0, nil, &UnsupportedError{
			Err: fmt.Errorf("workbook is larger than %d bytes and this storage cannot be read in place", MaxBufferedXlsxBytes),
		}
	}
	return bytes.NewReader(buf), int64(len(buf)), nopCloser{}, nil
}
