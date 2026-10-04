package fileutil

import (
	"context"
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ExportXlsxParams is one .qsheet to stream out as an .xlsx.
type ExportXlsxParams struct {
	// Ctx bounds the read.
	Ctx context.Context
	// Registry reads through the VFS when no serial routes past it.
	Registry vfs.Registry
	// Storage serves the request for a device-scoped path, or when there is
	// no VFS namespace to route to.
	Storage *storageutil.StorageService
	// FilePath is the files-relative path of the .qsheet.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Out receives the workbook as each tab is read. Nothing is written to it
	// before the first tab has been read and checked, so a source that is
	// missing, not a .qsheet, or whose first tab is past the limits fails
	// with Out untouched.
	Out io.Writer
}

// ExportXlsxResult reports the workbook that was written.
type ExportXlsxResult struct {
	// Tabs, Rows and Cells are what the sheet came to.
	Tabs  int
	Rows  int
	Cells int
}

// ExportQsheetToXlsx streams the .qsheet at params.FilePath to params.Out as
// an .xlsx that Excel, Numbers, LibreOffice and Google Sheets open, every tab
// a worksheet (#2696). It only reads: nothing is written beside the sheet, so
// the file tree does not change and there is no event to publish. What carries
// across, and why formulas go as text, is [xlsxutil.ExportQsheet]'s to say.
//
// The .qsheet is read front to back one tab at a time and the workbook is
// written as it goes, so neither is held whole.
func ExportQsheetToXlsx(params ExportXlsxParams) (ExportXlsxResult, error) {
	if !strings.EqualFold(filepath.Ext(params.FilePath), ".qsheet") {
		return ExportXlsxResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a Quark spreadsheet: %s", filepath.Base(params.FilePath)),
		}
	}

	source, _, err := openExportFile(params.Ctx, params.Registry, params.Storage, params.FilePath, params.Serial)
	if err != nil {
		return ExportXlsxResult{}, err
	}
	defer source.Close()

	exported, err := xlsxutil.ExportQsheet(xlsxutil.ExportQsheetParams{Source: source, Out: params.Out})
	return ExportXlsxResult{Tabs: exported.Tabs, Rows: exported.Rows, Cells: exported.Cells}, convertError(err)
}

// XlsxExportName is the name to offer the export of the .qsheet at filePath
// under: the sheet's own, with .xlsx in place of .qsheet.
func XlsxExportName(filePath string) string {
	base := filepath.Base(filePath)
	return strings.TrimSuffix(base, filepath.Ext(base)) + ".xlsx"
}

// openExportFile opens the file an export reads, as a stream, with its size
// in bytes: through the VFS when no serial routes past it, through the storage
// service otherwise.
func openExportFile(
	ctx context.Context, registry vfs.Registry, storage *storageutil.StorageService, filePath, serial string,
) (io.ReadCloser, int64, error) {
	if serial == "" {
		if fsys := FilesVFS(registry); fsys != nil {
			info, err := fsys.Stat(ctx, filePath)
			if err != nil {
				return nil, 0, notFound(err)
			}
			if info.IsDir {
				return nil, 0, &UnsupportedError{Err: fmt.Errorf("not a file: %s", filePath)}
			}
			r, err := fsys.Open(ctx, filePath)
			if err != nil {
				return nil, 0, notFound(err)
			}
			return r, info.Size, nil
		}
	}
	if storage == nil {
		return nil, 0, ErrNoFilesNamespace
	}
	opened, err := OpenDownload(OpenDownloadParams{
		Storage:  storage,
		FilePath: filePath,
		Serial:   serial,
	})
	if err != nil {
		return nil, 0, err
	}
	if opened.File == nil {
		return nil, 0, &UnsupportedError{Err: fmt.Errorf("not a file: %s", filePath)}
	}
	info, err := opened.File.Stat()
	if err != nil {
		_ = opened.File.Close()
		return nil, 0, err
	}
	return opened.File, info.Size(), nil
}
