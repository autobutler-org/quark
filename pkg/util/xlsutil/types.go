package xlsutil

import (
	"bufio"
	"io"
	"time"

	"github.com/richardlehane/mscfb"
)

// BIFF8 record types this reader acts on. Everything else is skipped by its
// length, which is how the format means unknown records to be read.
const (
	recFormula    = 0x0006
	recEOF        = 0x000A
	recDateMode   = 0x0022
	recFilePass   = 0x002F
	recContinue   = 0x003C
	recBoundSheet = 0x0085
	recMulRK      = 0x00BD
	recRString    = 0x00D6
	recXF         = 0x00E0
	recSST        = 0x00FC
	recLabelSST   = 0x00FD
	recNumber     = 0x0203
	recLabel      = 0x0204
	recBoolErr    = 0x0205
	recString     = 0x0207
	recRK         = 0x027E
	recFormat     = 0x041E
	recBOF        = 0x0809
)

const (
	// maxRecordBytes is the longest record body BIFF8 allows. Anything
	// longer is not a BIFF8 record, so it fails the file rather than sizing a
	// buffer.
	maxRecordBytes = 8224
	// biff8Version is the BOF version of Excel 97 and later. Excel 5.0/95
	// wrote 0x0500, which this reader does not read.
	biff8Version = 0x0600
	// bofGlobals and bofWorksheet are the BOF substream types this reader
	// reads.
	bofGlobals   = 0x0005
	bofWorksheet = 0x0010
	// sheetTypeWorksheet is BOUNDSHEET's type for a worksheet; charts, macro
	// sheets and VBA modules are the other values, and are skipped.
	sheetTypeWorksheet = 0
)

// Read-budget costs. Every ReadAt the container library makes is charged its
// length plus perCallCost, so a flood of tiny reads (a sector chain walked
// again and again) is charged for the work it causes, not just its bytes.
// Reads served from the cached block cost their length only.
const (
	perCallCost   = 64
	cacheBlock    = 4096
	maxCachedRead = 16
)

// budgetReaderAt sits between the container library and the source. It
// charges each read against a budget, so no sector chain, however it loops,
// reads more than the budget allows, and it keeps one aligned block cached
// for the four-byte allocation-table lookups the library makes per sector.
type budgetReaderAt struct {
	ra        io.ReaderAt
	remaining int64
	// exhausted is set once a read was refused for want of budget. The
	// library rewraps the error it is handed, so this is how the refusal is
	// recognized afterwards.
	exhausted bool
	// err is the first failure of the source itself: an I/O error, not a
	// malformed file, so it is reported as such.
	err error

	block    [cacheBlock]byte
	blockOff int64
	blockLen int
}

// guardedStream is the Workbook stream as the container library reads it,
// with any panic in that library turned into an error for the file.
type guardedStream struct {
	f *mscfb.File
}

// recordReader reads BIFF8 records from the Workbook stream through a
// buffered reader, tracking the logical offset so a sheet's BOF can be
// reached without seeking when it is already buffered.
type recordReader struct {
	file   io.ReadSeeker
	br     *bufio.Reader
	budget *budgetReaderAt
	pos    int64
	size   int64
	head   [4]byte
	buf    [maxRecordBytes]byte
}

// continuedReader reads a value that may run on into CONTINUE records: the
// shared string table, and a formula's string result. Bytes are taken from
// the current record and, once it is spent, from the next CONTINUE.
type continuedReader struct {
	rr   *recordReader
	data []byte
}

// sheet is one worksheet named by BOUNDSHEET: its tab name and the stream
// offset of its BOF.
type sheet struct {
	name   string
	offset int64
}

// dateKind says which parts of a date a number format displays.
type dateKind int

const (
	notDate dateKind = iota
	dateOnly
	timeOnly
	dateAndTime
)

// workbook is what the globals substream says about the whole file.
type workbook struct {
	sheets []sheet
	shared []string
	// xfDates is the date kind of each XF record, in record order, which is
	// the order a cell's XF index counts in.
	xfDates []dateKind
	epoch   time.Time
}

// sheetExtent is how much of a worksheet holds anything, measured from its
// cells rather than from its DIMENSIONS record, which is the producer's
// claim.
type sheetExtent struct {
	rows  int
	width int
}

// cellFunc receives one cell's display text, by zero-based row and column.
type cellFunc func(row, col int, text string) error
