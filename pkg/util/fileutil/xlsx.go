package fileutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ConvertXlsxParams converts one .xlsx or .xlsm into the .qsheet the Sheets
// editor opens, written beside the workbook it came from.
type ConvertXlsxParams struct {
	// Ctx bounds the read and the write.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
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

	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return ConvertXlsxResult{}, err
	}
	existed, err := exists(params.Ctx, fsys, target)
	if err != nil {
		return ConvertXlsxResult{}, err
	}
	if existed && !params.Overwrite {
		return ConvertXlsxResult{}, fmt.Errorf("%w: %s already exists", vfs.ErrConflict, target)
	}

	source, size, closer, err := openXlsx(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return ConvertXlsxResult{}, err
	}
	defer closer.Close()

	// The conversion writes onto a pipe the destination reads from, so the
	// .qsheet is never held whole on either side.
	dest := uploadutil.Destination{
		Registry: params.Registry,
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
		discardTemp(params.Ctx, fsys, tempPath)
		return ConvertXlsxResult{}, convertError(outcome.err)
	}
	if writeErr != nil {
		discardTemp(params.Ctx, fsys, tempPath)
		return ConvertXlsxResult{}, writeErr
	}

	if _, err := MoveFile(MoveFileParams{
		Ctx:             params.Ctx,
		Registry:        params.Registry,
		EventBus:        params.EventBus,
		OldFilePath:     tempPath,
		NewFilePath:     target,
		OldDeviceSerial: params.Serial,
		NewDeviceSerial: params.Serial,
	}); err != nil {
		discardTemp(params.Ctx, fsys, tempPath)
		return ConvertXlsxResult{}, err
	}

	return ConvertXlsxResult{
		Path:     target,
		Replaced: existed,
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
	if errors.Is(err, xlsxutil.ErrNotSpreadsheet) || errors.Is(err, xlsxutil.ErrNotQsheet) ||
		errors.Is(err, xlsxutil.ErrTooLarge) {
		return &UnsupportedError{Err: err}
	}
	return err
}

// cleanRelPath normalizes a files-relative path to the forward-slash form the
// VFS and the storage service both address files by.
func cleanRelPath(filePath string) string {
	return strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(filePath)), "/")
}

// discardTemp removes the half-written conversion. It is best effort: the
// error that got us here is the one worth reporting, and a leftover temporary
// file is a smaller problem than losing it.
func discardTemp(ctx context.Context, fsys vfs.VFS, tempPath string) {
	err := fsys.Delete(ctx, tempPath, vfs.DeleteOptions{})
	if err != nil && !errors.Is(err, vfs.ErrNotFound) {
		slog.Warn("xlsx: could not remove the partial conversion", "path", tempPath, "err", err)
	}
}

// openXlsx opens a workbook for random access, which is what reading a zip
// needs: the central directory sits at the end of the file. A vfs.File reads
// at an offset, so the workbook is read in place and nothing is copied.
func openXlsx(ctx context.Context, fsys vfs.VFS, filePath string) (io.ReaderAt, int64, io.Closer, error) {
	f, err := fsys.Open(ctx, filePath)
	if errors.Is(err, vfs.ErrIsDirectory) {
		return nil, 0, nil, &UnsupportedError{Err: fmt.Errorf("not a file: %s", filePath)}
	}
	if err != nil {
		return nil, 0, nil, notFound(err)
	}
	size, err := f.Seek(0, io.SeekEnd)
	if err != nil {
		f.Close()
		return nil, 0, nil, err
	}
	return f, size, f, nil
}
