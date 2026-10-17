package xlsutil

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/richardlehane/mscfb"
)

// errBudget is what budgetReaderAt hands the container library when a read
// would pass the budget.
var errBudget = errors.New("read budget exhausted")

// openWorkbookStream opens the compound file and finds its Workbook stream.
// Opening is charged against MaxContainerReadBytes; the stream itself gets a
// budget proportional to its own size afterwards.
func openWorkbookStream(source io.ReaderAt, size int64) (*recordReader, error) {
	budget := &budgetReaderAt{ra: source, remaining: MaxContainerReadBytes, blockOff: -1}
	doc, err := openContainer(budget)
	if err != nil {
		return nil, budget.classify(fmt.Errorf("not a compound file: %w", err))
	}

	var stream *mscfb.File
	for _, f := range doc.File {
		if len(f.Path) != 0 || f.FileInfo().IsDir() {
			continue
		}
		switch {
		case strings.EqualFold(f.Name, "Workbook"):
			stream = f
		case strings.EqualFold(f.Name, "Book"):
			return nil, fmt.Errorf("%w: an Excel 5.0/95 workbook, which is older than this reader reads", ErrNotSpreadsheet)
		case strings.EqualFold(f.Name, "EncryptedPackage"):
			// A password-protected .xlsx is a compound file too, and is
			// sometimes named .xls.
			return nil, ErrEncrypted
		}
	}
	if stream == nil {
		return nil, fmt.Errorf("%w: no Workbook stream", ErrNotSpreadsheet)
	}
	if stream.Size > MaxStreamBytes {
		return nil, fmt.Errorf("%w: the Workbook stream is larger than %d bytes", ErrTooLarge, MaxStreamBytes)
	}
	// A stream's sectors are the file's sectors, so a stream larger than the
	// file can only be a sector chain that loops back on itself, read round
	// and round for as long as the stated size allows.
	if stream.Size > size {
		return nil, fmt.Errorf("%w: the Workbook stream claims more bytes than the file holds", ErrNotSpreadsheet)
	}

	// Reading the globals once and every sheet twice touches the stream about
	// three times, plus an allocation-table lookup per sector. Four times the
	// stream is room for that, and nothing like room for a sheet list that
	// names one large substream over and over.
	budget.remaining = 4*stream.Size + MaxContainerReadBytes
	guarded := guardedStream{f: stream}
	return &recordReader{
		file:   guarded,
		br:     bufio.NewReaderSize(guarded, 64<<10),
		budget: budget,
		size:   stream.Size,
	}, nil
}

// openContainer is mscfb.New with a panic in it reported as an error. The
// library is third-party code fed hostile bytes; a panic in it is a malformed
// file, not a crashed server. This package's own parsing runs outside any
// recover, so the fuzz target still finds its panics.
func openContainer(ra io.ReaderAt) (doc *mscfb.Reader, err error) {
	defer recoverInto(&err)
	return mscfb.New(ra)
}

// Read reads the stream through the library, recovering a panic.
func (g guardedStream) Read(p []byte) (n int, err error) {
	defer recoverInto(&err)
	return g.f.Read(p)
}

// Seek seeks the stream through the library, recovering a panic.
func (g guardedStream) Seek(offset int64, whence int) (n int64, err error) {
	defer recoverInto(&err)
	return g.f.Seek(offset, whence)
}

// recoverInto turns a panic in the deferring call into an error wrapping
// ErrNotSpreadsheet.
func recoverInto(err *error) {
	if p := recover(); p != nil {
		*err = fmt.Errorf("%w: malformed compound file (%v)", ErrNotSpreadsheet, p)
	}
}

// ReadAt charges the read against the budget, then serves it from the cached
// block when it is a small read inside it.
func (b *budgetReaderAt) ReadAt(p []byte, off int64) (int, error) {
	if off < 0 {
		return 0, errors.New("negative offset")
	}
	if len(p) <= maxCachedRead {
		if b.inBlock(p, off) {
			if !b.charge(int64(len(p))) {
				return 0, errBudget
			}
			return copy(p, b.block[off-b.blockOff:]), nil
		}
		if !b.charge(cacheBlock + perCallCost) {
			return 0, errBudget
		}
		start := off - off%cacheBlock
		n, err := b.ra.ReadAt(b.block[:], start)
		if err != nil && !errors.Is(err, io.EOF) {
			b.blockOff = -1
			return 0, b.sourceError(err)
		}
		b.blockOff, b.blockLen = start, n
		if !b.inBlock(p, off) {
			return 0, io.EOF
		}
		return copy(p, b.block[off-b.blockOff:]), nil
	}

	if !b.charge(int64(len(p)) + perCallCost) {
		return 0, errBudget
	}
	n, err := b.ra.ReadAt(p, off)
	if err != nil && !errors.Is(err, io.EOF) {
		return n, b.sourceError(err)
	}
	return n, err
}

// inBlock reports whether the cached block holds all of p's range.
func (b *budgetReaderAt) inBlock(p []byte, off int64) bool {
	return b.blockOff >= 0 && off >= b.blockOff && off+int64(len(p)) <= b.blockOff+int64(b.blockLen)
}

// charge takes cost from the budget, or reports that it cannot.
func (b *budgetReaderAt) charge(cost int64) bool {
	if cost > b.remaining {
		b.exhausted = true
		return false
	}
	b.remaining -= cost
	return true
}

// sourceError records the source's own failure, which the library is about
// to rewrap as a format error, so classify can tell the two apart.
func (b *budgetReaderAt) sourceError(err error) error {
	if b.err == nil {
		b.err = err
	}
	return err
}

// classify turns a failure out of the container library into this package's
// errors. The library reports everything as its own error type, so the
// budget and the source are asked what really happened.
func (b *budgetReaderAt) classify(err error) error {
	switch {
	case b.err != nil:
		return fmt.Errorf("xlsutil: reading the file: %w", b.err)
	case b.exhausted:
		return fmt.Errorf("%w: its sector chains read far past the file's own size", ErrNotSpreadsheet)
	}
	return fmt.Errorf("%w: %v", ErrNotSpreadsheet, err)
}
