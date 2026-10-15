package xlsutil

// cspell:ignore RSTRING

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"

	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
)

// walkSheet reads one worksheet substream from its BOF to its EOF and hands
// each cell's display text to fn. A cell that displays nothing is not handed
// on. Records inside a nested substream — a chart embedded in the sheet has
// its own BOF and EOF — are not the sheet's cells and are skipped.
//
// A sheet whose stream ends before its EOF ends there: what was read is kept.
func walkSheet(rr *recordReader, book *workbook, s sheet, fn cellFunc) error {
	if err := rr.seek(s.offset); err != nil {
		return err
	}
	typ, data, err := rr.next()
	if err != nil {
		if errors.Is(err, io.EOF) {
			return fmt.Errorf("%w: a sheet offset at the end of the stream", ErrNotSpreadsheet)
		}
		return err
	}
	if err := checkBOF(typ, data, bofWorksheet); err != nil {
		return err
	}

	depth := 1
	// A FORMULA whose result is a string leaves it to the STRING record
	// that follows; pending is the cell waiting for it.
	pending, pendingRow, pendingCol := false, 0, 0
	for depth > 0 {
		typ, data, err := rr.next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		switch typ {
		case recBOF:
			depth++
			continue
		case recEOF:
			depth--
			continue
		}
		if depth > 1 {
			continue
		}

		if typ == recString {
			if !pending {
				continue
			}
			pending = false
			cr := &continuedReader{rr: rr, data: data}
			text, err := cr.unicodeString()
			if err != nil {
				return err
			}
			if err := emitCell(fn, pendingRow, pendingCol, text); err != nil {
				return err
			}
			continue
		}

		if len(data) < 6 {
			continue
		}
		row := int(binary.LittleEndian.Uint16(data))
		col := int(binary.LittleEndian.Uint16(data[2:]))
		xf := int(binary.LittleEndian.Uint16(data[4:]))
		var text string
		switch typ {
		case recNumber:
			if len(data) < 14 {
				continue
			}
			text = book.numberText(float64At(data[6:]), xf)

		case recRK:
			if len(data) < 10 {
				continue
			}
			text = book.numberText(rkNumber(binary.LittleEndian.Uint32(data[6:])), xf)

		case recMulRK:
			// Several RK cells in a row: (XF, RK) pairs from the first column,
			// closed by the last column's index.
			for i, off := 0, 4; off+6 <= len(data)-2; i, off = i+1, off+6 {
				xf := int(binary.LittleEndian.Uint16(data[off:]))
				v := rkNumber(binary.LittleEndian.Uint32(data[off+2:]))
				if err := emitCell(fn, row, col+i, book.numberText(v, xf)); err != nil {
					return err
				}
			}
			continue

		case recLabelSST:
			if len(data) < 10 {
				continue
			}
			if i := binary.LittleEndian.Uint32(data[6:]); int64(i) < int64(len(book.shared)) {
				text = book.shared[i]
			}

		case recLabel, recRString:
			// LABEL is the pre-SST string cell, which some writers still use;
			// RSTRING adds formatting runs after the same string.
			text, _ = shortString(data[6:], 2)

		case recBoolErr:
			if len(data) < 8 {
				continue
			}
			text = boolErrText(data[6], data[7] != 0)

		case recFormula:
			if len(data) < 14 {
				continue
			}
			value := data[6:14]
			if binary.LittleEndian.Uint16(value[6:]) != 0xFFFF {
				text = book.numberText(float64At(value), xf)
				break
			}
			switch value[0] {
			case 0x00:
				pending, pendingRow, pendingCol = true, row, col
				continue
			case 0x01:
				text = boolErrText(value[2], false)
			case 0x02:
				text = boolErrText(value[2], true)
			}

		default:
			continue
		}
		pending = false
		if err := emitCell(fn, row, col, text); err != nil {
			return err
		}
	}
	return nil
}

// emitCell hands a cell with something to display on to fn.
func emitCell(fn cellFunc, row, col int, text string) error {
	if text == "" {
		return nil
	}
	return fn(row, col, text)
}

// boolErrText is what a BOOLERR cell, or a formula's boolean or error
// result, displays. Excel renders a boolean uppercase, and the editor's own
// formula language reads TRUE and FALSE the same way.
func boolErrText(value byte, isError bool) string {
	if isError {
		if code, ok := errorCodes[value]; ok {
			return code
		}
		return "#VALUE!"
	}
	if value != 0 {
		return "TRUE"
	}
	return "FALSE"
}

// measureSheet walks a worksheet for its extent: the last row and the
// widest column holding anything. The editor takes its column count from the
// first row, so the width has to be known before the first row is written;
// measuring in its own pass keeps two integers rather than the sheet.
func measureSheet(rr *recordReader, book *workbook, s sheet) (sheetExtent, error) {
	var extent sheetExtent
	err := walkSheet(rr, book, s, func(row, col int, _ string) error {
		if col >= xlsxutil.MaxColumns {
			return fmt.Errorf("%w: a sheet is wider than %d columns", ErrTooLarge, xlsxutil.MaxColumns)
		}
		if row >= xlsxutil.MaxRows {
			return fmt.Errorf("%w: a sheet is longer than %d rows", ErrTooLarge, xlsxutil.MaxRows)
		}
		extent.rows = max(extent.rows, row+1)
		extent.width = max(extent.width, col+1)
		return nil
	})
	return extent, err
}
