package xlsxutil

import (
	"archive/zip"
	"bufio"
	"io"
	"time"
)

// workbook is a resolved .xlsx package: the parts, indexed by name, and the
// worksheets in the order the workbook lists them.
type workbook struct {
	parts  partIndex
	sheets []sheetRef
	// epoch is the day serial 0 denotes. Almost every workbook counts from
	// 1899-12-30; one saved with the 1904 date system counts from 1904-01-01.
	epoch time.Time
}

// sheetRef is one worksheet: the tab name the user gave it, and the part
// holding its rows.
type sheetRef struct {
	name string
	part *zip.File
}

// partIndex maps a package-relative part name ("xl/worksheets/sheet1.xml") to
// its archive entry. Built once so a lookup does not walk the whole archive.
type partIndex map[string]*zip.File

// relationship is one entry of a .rels part: Target is resolved relative to
// the directory of the part the relationships belong to.
type relationship struct {
	ID     string `xml:"Id,attr"`
	Type   string `xml:"Type,attr"`
	Target string `xml:"Target,attr"`
}

// sharedItem is one entry of the shared-string table. Plain text sits in T;
// rich text is split across formatting runs in R, whose pieces concatenate
// back into the string the cell shows. Phonetic hints (rPh) nest their own
// <t> deeper and so match neither field, which is what we want.
type sharedItem struct {
	T *string `xml:"t"`
	R []struct {
		T string `xml:"t"`
	} `xml:"r"`
}

// sheetRow is one <row> of a worksheet. Index is the row's 1-based position,
// which is declared rather than implied: a worksheet stores only the rows that
// hold something, so a gap in Index is a run of empty rows.
type sheetRow struct {
	Index int         `xml:"r,attr"`
	Cells []sheetCell `xml:"c"`
}

// sheetCell is one <c> of a row.
type sheetCell struct {
	// Ref is the cell's address ("B7"). Like a row's index it is declared, so
	// a gap between two cells is a run of empty ones.
	Ref string `xml:"r,attr"`
	// Type says how V is read: "s" indexes the shared-string table, "b" is a
	// boolean, "e" an error, "str" a formula's string result, "inlineStr" text
	// carried in IS, and an empty type is a number.
	Type string `xml:"t,attr"`
	// Style indexes the cell formats in styles.xml, which is the only place a
	// date says it is one.
	Style *int `xml:"s,attr"`
	// Value is the stored value, or a formula's cached result.
	Value *string `xml:"v"`
	// Inline is the text of an inlineStr cell, which carries it here instead
	// of in the shared table.
	Inline *sharedItem `xml:"is"`
}

// numberFormats says which cell styles render as dates, which is not something
// a cell records: a date is a number whose format code makes it one.
type numberFormats struct {
	// dateStyles maps a cell-format index to the kind of date it displays.
	dateStyles map[int]dateKind
}

// dateKind is the part of a date-formatted number that its format code shows.
type dateKind int

const (
	// notDate is a number displayed as a number.
	notDate dateKind = iota
	// dateOnly shows the day but not the time.
	dateOnly
	// timeOnly shows the time but not the day.
	timeOnly
	// dateAndTime shows both.
	dateAndTime
)

// qsheetTab is one tab of a .qsheet as the editor saves it: the cells, and
// the layout and formats that sit beside them. Keys the export does not use
// (filters, row heights) are not decoded.
type qsheetTab struct {
	Name string `json:"name"`
	Data struct {
		Rows [][]any `json:"rows"`
	} `json:"data"`
	ColumnWidths  []float64      `json:"columnWidths"`
	FrozenRows    int            `json:"frozenRows"`
	FrozenColumns int            `json:"frozenColumns"`
	Formats       []qsheetFormat `json:"formats"`
}

// qsheetFormat is one formatted cell, as the editor's CellFormat.toJson
// writes it beside the cell's row and column. Every field but the position is
// optional, and a missing one is the plain default.
type qsheetFormat struct {
	Row          int    `json:"row"`
	Col          int    `json:"col"`
	Bold         bool   `json:"bold"`
	Italic       bool   `json:"italic"`
	TextColor    *int64 `json:"textColor"`
	FillColor    *int64 `json:"fillColor"`
	Align        string `json:"align"`
	NumberFormat string `json:"numberFormat"`
	Decimals     *int   `json:"decimals"`
}

// cellStyle is the part of a qsheetFormat a workbook stores, and the key the
// export dedupes cell formats by: equal styles share one cellXfs entry.
type cellStyle struct {
	bold, italic bool
	textColor    string
	fillColor    string
	align        string
	numFmt       string
}

// font is the part of a cellStyle stored in the workbook's font table.
type font struct {
	bold, italic bool
	color        string
}

// styleTable collects the distinct cell styles a workbook uses, in the order
// they are first met, so styles.xml can be written once every tab is done.
// Index 0 of each table is the default the format requires.
type styleTable struct {
	xfs     []cellStyle
	xfIndex map[cellStyle]int
	fonts   []font
	fontIdx map[font]int
	fills   []string
	fillIdx map[string]int
	numFmts []string
	fmtIdx  map[string]int
}

// cappedReader reads until remaining runs out, then fails with
// [ErrTooLarge] instead of reporting a clean end the decoder would trust.
type cappedReader struct {
	r         io.Reader
	remaining int64
}

// partWriter writes one worksheet part. A bufio.Writer keeps its first write
// error and reports it from Flush, so the part's many small writes need no
// checks of their own.
type partWriter struct {
	*bufio.Writer
}
