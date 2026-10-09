package fileutil

import (
	"context"
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ExportXlsxParams is one .qsheet to stream out as an .xlsx.
type ExportXlsxParams struct {
	// Ctx bounds the read.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
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

	source, _, err := openExportFile(params.Ctx, params.Registry, params.FilePath, params.Serial)
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
// in bytes, from the namespace of the device serial names.
func openExportFile(ctx context.Context, registry vfs.Registry, filePath, serial string) (io.ReadCloser, int64, error) {
	fsys, err := FilesVFS(registry, serial)
	if err != nil {
		return nil, 0, err
	}
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
