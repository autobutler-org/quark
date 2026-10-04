// Package xlsxutil reads an OOXML spreadsheet (.xlsx / .xlsm) and rewrites it
// as the .qsheet JSON envelope Quark's Sheets editor already understands, and
// writes a .qsheet back out as an .xlsx for export ([ExportQsheet]):
//
//	{"tabs":[{"name":"Sheet1","data":{"rows":[["a","b"], …]}}]}
//
// Converting on import, rather than teaching Sheets a second file format, is
// the same trade the CSV importer already makes (#1019): .qsheet stays the one
// format the editor has to understand, and the whole editor is reused as-is.
//
// An .xlsx is a zip of XML parts, so reading one needs random access to the
// archive but not the archive in memory: the caller supplies an [io.ReaderAt]
// and its size, every part is decoded as a token stream, and rows are written
// onto Out as they are read. Only the shared-string table is held whole, which
// is inherent to the format — a cell references its text by index — so it is
// bounded by [MaxSharedStringBytes] instead.
package xlsxutil

import (
	"archive/zip"
	"errors"
	"fmt"
	"io"
)

// Conversion limits. A workbook is user-supplied and its dimensions are
// declared inside it, so every one of these is checked against what is
// actually read rather than trusted from the file's own headers.
const (
	// MaxSheets is the number of worksheets converted from one workbook.
	MaxSheets = 64
	// MaxRows is the number of rows converted from one worksheet. Excel's own
	// ceiling is 1,048,576; the editor renders every row it is handed, so the
	// useful limit is well below that.
	MaxRows = 100_000
	// MaxColumns is Excel's own column ceiling (XFD).
	MaxColumns = 16_384
	// MaxCells bounds the whole workbook, so many modest sheets cost no more
	// than one large one.
	MaxCells = 1_000_000
	// MaxSharedStringBytes bounds the one table that cannot be streamed.
	MaxSharedStringBytes = 64 << 20 // 64 MiB
	// MaxPartBytes bounds what any single XML part of the package may expand
	// to. A part is compressed, so its size in the archive says nothing about
	// what reading it costs.
	MaxPartBytes = 256 << 20 // 256 MiB
	// MaxSharedStrings bounds the string table by count as well as by bytes:
	// a table of empty entries costs nothing to store and a slot each to hold.
	MaxSharedStrings = 4_000_000
)

var (
	// ErrNotSpreadsheet reports a file that is not an OOXML workbook: not a
	// zip, or a zip with no workbook part. The file is at fault, not the
	// server, so callers answer 400 for it.
	ErrNotSpreadsheet = errors.New("xlsxutil: not an xlsx workbook")
	// ErrTooLarge reports a workbook past one of the limits above. Also the
	// caller's file, and also a 400.
	ErrTooLarge = errors.New("xlsxutil: workbook exceeds conversion limits")
	// ErrNotQsheet reports an export source that is not a .qsheet envelope.
	// Like the two above, it is the caller's file and a 400.
	ErrNotQsheet = errors.New("xlsxutil: not a qsheet")
)

// ConvertToQsheetParams is one workbook on its way to becoming a .qsheet.
type ConvertToQsheetParams struct {
	// Source is the .xlsx package. A zip is read from its trailing central
	// directory inwards, so this is a ReaderAt rather than a stream — see the
	// package doc.
	Source io.ReaderAt
	// Size is Source's length in bytes, from the source's own Stat.
	Size int64
	// Out receives the .qsheet JSON envelope, written as the rows are read.
	Out io.Writer
}

// ConvertToQsheetResult reports what the converted workbook came to, for the
// caller to log or hand back.
type ConvertToQsheetResult struct {
	// Tabs is the number of worksheets written.
	Tabs int
	// Rows is the number of rows written across every tab.
	Rows int
	// Cells is the number of cells written across every tab.
	Cells int
}

// ConvertToQsheet reads the workbook in params.Source and writes the
// equivalent .qsheet envelope to params.Out.
//
// Cells carry what the workbook says they display: shared and inline strings
// verbatim, numbers as stored, booleans as TRUE/FALSE, and a date-formatted
// number as the date it denotes. A formula cell contributes the cached result
// Excel last computed rather than the formula itself — the editor's formula
// dialect covers common arithmetic but not the whole of Excel's, so carrying
// formulas across would turn an unsupported function into a visible error
// where the workbook showed a value.
//
// Errors wrap [ErrNotQsheet] or [ErrTooLarge] when the workbook is at
// fault; anything else is a read or write failure.
func ConvertToQsheet(params ConvertToQsheetParams) (ConvertToQsheetResult, error) {
	if params.Source == nil || params.Out == nil {
		return ConvertToQsheetResult{}, errors.New("xlsxutil: Source and Out are required")
	}
	if params.Size <= 0 {
		return ConvertToQsheetResult{}, fmt.Errorf("%w: empty file", ErrNotSpreadsheet)
	}

	zr, err := zip.NewReader(params.Source, params.Size)
	if err != nil {
		return ConvertToQsheetResult{}, fmt.Errorf("%w: %v", ErrNotSpreadsheet, err)
	}

	book, err := readWorkbook(zr)
	if err != nil {
		return ConvertToQsheetResult{}, err
	}

	shared, err := readSharedStrings(book.parts)
	if err != nil {
		return ConvertToQsheetResult{}, err
	}

	styles, err := readStyles(book.parts)
	if err != nil {
		return ConvertToQsheetResult{}, err
	}

	return writeQsheet(params.Out, book, shared, styles)
}

// MaxQsheetBytes bounds the .qsheet an export reads. The document is decoded
// one tab at a time, so this caps what a single oversized tab can cost.
const MaxQsheetBytes = 256 << 20 // 256 MiB

// ExportQsheetParams is one .qsheet on its way to becoming an .xlsx.
type ExportQsheetParams struct {
	// Source is the .qsheet JSON envelope. It is read once, front to back.
	Source io.Reader
	// Out receives the .xlsx package, written as each tab is read. A zip is
	// written front to back, so this is a plain stream.
	Out io.Writer
}

// ExportQsheetResult reports what the exported workbook came to.
type ExportQsheetResult struct {
	// Tabs is the number of worksheets written.
	Tabs int
	// Rows is the number of rows written across every worksheet.
	Rows int
	// Cells is the number of non-empty cells written across every worksheet.
	Cells int
}

// ExportQsheet reads the .qsheet in params.Source and writes the equivalent
// workbook to params.Out, one worksheet per tab, in tab order.
//
// A cell whose text is a plain decimal number is written as a number, so the
// tab's number formats apply to it in Excel; everything else is text. A
// formula is written as its text ("=SUM(A1:A3)") rather than as a formula:
// the editor's dialect is not Excel's (it has == and !=, for one), and Quark
// has no evaluator on the server to supply the cached result Excel expects
// beside a formula. Bold, italic, text and fill colors, alignment and number
// formats carry across, as do column widths and frozen rows and columns.
//
// Only one tab is held in memory at a time. Errors wrap [ErrNotQsheet]
// when the source is not a .qsheet and [ErrTooLarge] past the conversion
// limits; anything else is a read or write failure.
func ExportQsheet(params ExportQsheetParams) (ExportQsheetResult, error) {
	if params.Source == nil || params.Out == nil {
		return ExportQsheetResult{}, errors.New("xlsxutil: Source and Out are required")
	}
	return writeXlsx(params.Out, &cappedReader{r: params.Source, remaining: MaxQsheetBytes})
}
