package xlsutil

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"

	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
)

// readGlobals reads the workbook globals substream, which opens the stream:
// the sheet list, the shared string table, the number formats and the date
// system. It stops at the substream's EOF, leaving the sheets to be read by
// their offsets.
func readGlobals(rr *recordReader) (workbook, error) {
	book := workbook{epoch: excelEpoch}
	typ, data, err := rr.next()
	if err != nil {
		if errors.Is(err, io.EOF) {
			return book, fmt.Errorf("%w: an empty Workbook stream", ErrNotSpreadsheet)
		}
		return book, err
	}
	if err := checkBOF(typ, data, bofGlobals); err != nil {
		return book, err
	}

	custom := map[int]dateKind{}
	var xfFormats []int
	for {
		typ, data, err := rr.next()
		if errors.Is(err, io.EOF) {
			return book, fmt.Errorf("%w: the workbook globals never end", ErrNotSpreadsheet)
		}
		if err != nil {
			return book, err
		}

		switch typ {
		case recEOF:
			book.xfDates = make([]dateKind, len(xfFormats))
			for i, id := range xfFormats {
				kind, ok := custom[id]
				if !ok {
					kind = builtinDateFormats[id]
				}
				book.xfDates[i] = kind
			}
			return book, nil

		case recFilePass:
			return book, ErrEncrypted

		case recDateMode:
			if len(data) >= 2 && binary.LittleEndian.Uint16(data) == 1 {
				book.epoch = excelEpoch1904
			}

		case recBoundSheet:
			if len(data) < 6 || data[5] != sheetTypeWorksheet {
				continue
			}
			name, ok := shortString(data[6:], 1)
			if !ok {
				return book, fmt.Errorf("%w: a malformed sheet name", ErrNotSpreadsheet)
			}
			if len(book.sheets) == xlsxutil.MaxSheets {
				return book, fmt.Errorf("%w: the workbook holds more than %d sheets", ErrTooLarge, xlsxutil.MaxSheets)
			}
			book.sheets = append(book.sheets, sheet{
				name:   name,
				offset: int64(binary.LittleEndian.Uint32(data)),
			})

		case recFormat:
			if len(data) < 2 {
				continue
			}
			code, ok := shortString(data[2:], 2)
			if !ok {
				continue
			}
			id := int(binary.LittleEndian.Uint16(data))
			if _, seen := custom[id]; !seen && len(custom) == MaxFormats {
				return book, fmt.Errorf("%w: more than %d number formats", ErrTooLarge, MaxFormats)
			}
			custom[id] = dateKindOf(code)

		case recXF:
			if len(xfFormats) == MaxXFs {
				return book, fmt.Errorf("%w: more than %d cell formats", ErrTooLarge, MaxXFs)
			}
			id := 0
			if len(data) >= 4 {
				id = int(binary.LittleEndian.Uint16(data[2:]))
			}
			xfFormats = append(xfFormats, id)

		case recSST:
			if book.shared != nil {
				return book, fmt.Errorf("%w: a second shared string table", ErrNotSpreadsheet)
			}
			if book.shared, err = readSST(rr, data); err != nil {
				return book, err
			}
		}
	}
}

// checkBOF accepts a BIFF8 BOF record opening a substream of the given type.
func checkBOF(typ uint16, data []byte, want uint16) error {
	if typ != recBOF || len(data) < 4 {
		return fmt.Errorf("%w: the stream does not open with a BOF record", ErrNotSpreadsheet)
	}
	if version := binary.LittleEndian.Uint16(data); version != biff8Version {
		return fmt.Errorf("%w: BIFF version %#04x; only Excel 97 and later (BIFF8) is read", ErrNotSpreadsheet, version)
	}
	if got := binary.LittleEndian.Uint16(data[2:]); got != want {
		return fmt.Errorf("%w: a substream of type %#04x where %#04x was expected", ErrNotSpreadsheet, got, want)
	}
	return nil
}

// readSST reads the shared string table, which opens in the SST record whose
// body is data and runs on into as many CONTINUE records as it needs. Its
// declared count is the producer's claim, so it sizes nothing: strings are
// read until the count or the records run out, and the table is bounded by
// what is actually held.
func readSST(rr *recordReader, data []byte) ([]string, error) {
	if len(data) < 8 {
		return nil, fmt.Errorf("%w: a truncated shared string table", ErrNotSpreadsheet)
	}
	declared := int64(binary.LittleEndian.Uint32(data[4:]))
	shared := make([]string, 0, min(declared, 4096))
	held := 0

	cr := &continuedReader{rr: rr, data: data[8:]}
	for int64(len(shared)) < declared {
		if len(cr.data) == 0 {
			if typ, ok := rr.peekType(); !ok || typ != recContinue {
				// Writers are known to overstate the count; the table is
				// what the records hold.
				break
			}
		}
		text, err := cr.richString()
		if err != nil {
			return nil, err
		}
		held += len(text)
		if held > xlsxutil.MaxSharedStringBytes {
			return nil, fmt.Errorf("%w: the shared strings exceed %d bytes", ErrTooLarge, xlsxutil.MaxSharedStringBytes)
		}
		if len(shared) == xlsxutil.MaxSharedStrings {
			return nil, fmt.Errorf("%w: more than %d shared strings", ErrTooLarge, xlsxutil.MaxSharedStrings)
		}
		shared = append(shared, text)
	}
	return shared, nil
}
