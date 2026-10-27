package fileutil

import (
	"context"
	"fmt"
	"io"
	"path/filepath"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// PreviewSheetParams says which workbook to preview and where the sheet
// goes.
type PreviewSheetParams struct {
	// Ctx ends the preview early when it is done.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// FilePath is the files-relative path of the workbook.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Out receives the .qsheet JSON. A file that is not the workbook its
	// name says fails before the first byte.
	Out io.Writer
}

// SheetPreview is the shape of what [PreviewSheet] writes, the .qsheet
// envelope the Sheets editor opens. It is never built whole: the rows are
// streamed as they are read.
type SheetPreview struct {
	// Tabs holds one entry per worksheet, in workbook order.
	Tabs []SheetPreviewTab `json:"tabs"`
}

// SheetPreviewTab is one worksheet of a [SheetPreview].
type SheetPreviewTab struct {
	// Name is the worksheet's name.
	Name string `json:"name"`
	// Data holds the worksheet's cells.
	Data SheetPreviewData `json:"data"`
}

// SheetPreviewData is a worksheet's cells as the value each displays, row by
// row.
type SheetPreviewData struct {
	Rows [][]string `json:"rows"`
}

// PreviewSheetResult reports what a preview came to.
type PreviewSheetResult struct {
	// Tabs, Rows and Cells are what the workbook holds.
	Tabs  int
	Rows  int
	Cells int
}

// PreviewSheet streams a workbook as the .qsheet the read-only sheet viewer
// draws (docs/architecture/read-only-documents.md, Spreadsheets). It is the
// conversion [ConvertXlsxToQsheet] runs, with the reader chosen by extension
// the same way, written to Out rather than beside the workbook: nothing is
// stored. A failure before output begins is a [NotFoundError] or an
// [UnsupportedError]; one after it leaves the envelope unclosed, which is how
// the client tells a cut-off sheet from a whole one.
func PreviewSheet(params PreviewSheetParams) (PreviewSheetResult, error) {
	if !IsWorkbookPath(params.FilePath) {
		return PreviewSheetResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a spreadsheet Quark can show: %s", filepath.Base(params.FilePath)),
		}
	}
	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return PreviewSheetResult{}, err
	}
	source, size, closer, err := openZip(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return PreviewSheetResult{}, err
	}
	defer closer.Close()

	result, err := convertWorkbook(params.Ctx, params.FilePath, source, size, params.Out)
	if err != nil {
		return PreviewSheetResult{}, convertError(err)
	}
	return PreviewSheetResult(result), nil
}
