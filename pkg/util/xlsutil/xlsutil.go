// Package xlsutil reads a legacy Excel 97–2003 workbook (.xls, BIFF8) and
// rewrites it as the same .qsheet JSON envelope [xlsxutil] writes for an
// .xlsx, so the Sheets UI has one format to understand whichever reader ran:
//
//	{"tabs":[{"name":"Sheet1","data":{"rows":[["a","b"], …]}}]}
//
// An .xls is a stream of BIFF8 records inside a Compound File Binary (OLE2)
// container. github.com/richardlehane/mscfb reads the container; this package
// reads the records. Only cell values are read: the shared string table,
// LABELSST, LABEL, NUMBER, RK, MULRK, BOOLERR, the cached result of a FORMULA,
// BOUNDSHEET for sheet names, and FORMAT, XF and DATEMODE for dates. Formulas
// are never evaluated, macros are never opened, and an encrypted workbook
// (FILEPASS) is refused with [ErrEncrypted].
//
// The file is untrusted. The caller supplies an [io.ReaderAt] and its size;
// the Workbook stream is read through, never held, and every read the
// container library makes is counted against a budget, so a cyclic sector
// chain or a sheet offset pointing back at itself costs one failed request.
// The shared string table is the one thing held whole, as in [xlsxutil], and
// it is bounded by [xlsxutil.MaxSharedStringBytes] and
// [xlsxutil.MaxSharedStrings]. The sheet limits are xlsxutil's too.
package xlsutil

// cspell:ignore DATEMODE

import (
	"errors"
	"fmt"
	"io"
)

// Reader limits beyond the sheet limits shared with [xlsxutil].
const (
	// MaxStreamBytes bounds the Workbook stream. The stream size is declared
	// by the container, so it is checked here and every read is counted as
	// well. It matches xlsxutil.MaxPartBytes, the bound on one worksheet part.
	MaxStreamBytes = 256 << 20 // 256 MiB
	// MaxContainerReadBytes bounds what opening the container may read: the
	// header, the sector allocation table index and the directory. A real
	// workbook's directory is a few sectors; a hostile one can chain the same
	// sectors into an arbitrarily long directory, and each entry costs heap.
	MaxContainerReadBytes = 4 << 20 // 4 MiB
	// MaxFormats bounds the FORMAT records held for date detection.
	MaxFormats = 4_096
	// MaxXFs bounds the XF records held for date detection. A cell names its
	// XF with a 16-bit index, so no workbook needs more.
	MaxXFs = 65_536
)

var (
	// ErrNotSpreadsheet reports a file that is not a BIFF8 workbook: not a
	// compound file, no Workbook stream, an older BIFF version, or records
	// that do not parse. The file is at fault, so callers answer 400.
	ErrNotSpreadsheet = errors.New("xlsutil: not an xls workbook")
	// ErrTooLarge reports a workbook past one of the limits above or one of
	// xlsxutil's sheet limits. Also the caller's file, and also a 400.
	ErrTooLarge = errors.New("xlsutil: workbook exceeds conversion limits")
	// ErrEncrypted reports a password-protected workbook. Quark never asks
	// for the password, so the file cannot be read; a 400 that says so.
	ErrEncrypted = errors.New("xlsutil: workbook is encrypted")
)

// ConvertToQsheetParams is one legacy workbook on its way to becoming a
// .qsheet.
type ConvertToQsheetParams struct {
	// Source is the .xls file. A compound file is a FAT-style sector format
	// read by offset, so this is a ReaderAt rather than a stream.
	Source io.ReaderAt
	// Size is Source's length in bytes, from the source's own Stat.
	Size int64
	// Out receives the .qsheet JSON envelope, written as the rows are read.
	Out io.Writer
}

// ConvertToQsheetResult reports what the converted workbook came to.
type ConvertToQsheetResult struct {
	// Tabs is the number of worksheets written.
	Tabs int
	// Rows is the number of rows written across every tab.
	Rows int
	// Cells is the number of non-empty cells written across every tab.
	Cells int
}

// ConvertToQsheet reads the workbook in params.Source and writes the
// equivalent .qsheet envelope to params.Out, one tab per worksheet in
// workbook order. Chart sheets and macro sheets are skipped.
//
// Cells carry what they display, as [xlsxutil.ConvertToQsheet] has them:
// strings verbatim, numbers as stored, booleans as TRUE/FALSE, errors as
// their #-code, a date-formatted number as the date it denotes, and a
// formula as the result Excel last computed.
//
// Errors wrap [ErrNotSpreadsheet], [ErrTooLarge] or [ErrEncrypted] when the
// workbook is at fault; anything else is a read or write failure.
func ConvertToQsheet(params ConvertToQsheetParams) (ConvertToQsheetResult, error) {
	if params.Source == nil || params.Out == nil {
		return ConvertToQsheetResult{}, errors.New("xlsutil: Source and Out are required")
	}
	if params.Size <= 0 {
		return ConvertToQsheetResult{}, fmt.Errorf("%w: empty file", ErrNotSpreadsheet)
	}
	stream, err := openWorkbookStream(params.Source, params.Size)
	if err != nil {
		return ConvertToQsheetResult{}, err
	}
	book, err := readGlobals(stream)
	if err != nil {
		return ConvertToQsheetResult{}, err
	}
	return writeQsheet(params.Out, stream, book)
}
