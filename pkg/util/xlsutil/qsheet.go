package xlsutil

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"

	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
)

// writeQsheet writes the .qsheet envelope for a workbook, one tab per
// worksheet. Every sheet is measured first, in one pass over the stream, so
// a workbook past the limits fails before a byte is written; the second pass
// streams each row onto w as it is read.
func writeQsheet(w io.Writer, rr *recordReader, book workbook) (ConvertToQsheetResult, error) {
	var result ConvertToQsheetResult

	extents := make([]sheetExtent, len(book.sheets))
	rows, cells := 0, 0
	for i, s := range book.sheets {
		extent, err := measureSheet(rr, &book, s)
		if err != nil {
			return result, err
		}
		rows += extent.rows
		cells += extent.rows * extent.width
		if rows > xlsxutil.MaxRows {
			return result, fmt.Errorf("%w: the workbook holds more than %d rows", ErrTooLarge, xlsxutil.MaxRows)
		}
		if cells > xlsxutil.MaxCells {
			return result, fmt.Errorf("%w: the workbook holds more than %d cells", ErrTooLarge, xlsxutil.MaxCells)
		}
		extents[i] = extent
	}

	out := bufio.NewWriter(w)
	if _, err := out.WriteString(`{"tabs":[`); err != nil {
		return result, err
	}
	for i, s := range book.sheets {
		if i > 0 {
			if err := out.WriteByte(','); err != nil {
				return result, err
			}
		}
		if _, err := out.WriteString(`{"name":`); err != nil {
			return result, err
		}
		if err := writeJSONString(out, s.name); err != nil {
			return result, err
		}
		if _, err := out.WriteString(`,"data":{"rows":[`); err != nil {
			return result, err
		}
		written, filled, err := streamSheet(out, rr, &book, s, extents[i])
		if err != nil {
			return result, err
		}
		if _, err := out.WriteString(`]}}`); err != nil {
			return result, err
		}
		result.Tabs++
		result.Rows += written
		result.Cells += filled
	}
	if _, err := out.WriteString(`]}`); err != nil {
		return result, err
	}
	return result, out.Flush()
}

// streamSheet writes a worksheet's rows, each exactly extent.width cells,
// for extent.rows rows. A sheet stores only the cells that hold something,
// so the rows and cells it leaves out are written as the empty strings they
// stand for and every value stays in its row and column.
//
// Excel writes a sheet's cells in row order. A cell for a row already
// written cannot be gone back to, so it is dropped. It returns the rows
// written and the cells filled.
func streamSheet(out *bufio.Writer, rr *recordReader, book *workbook, s sheet, extent sheetExtent) (int, int, error) {
	// The editor treats a sheet with no rows as a broken document and
	// replaces it with a blank one; an empty worksheet is written as the
	// single empty row that means the same thing.
	if extent.rows == 0 || extent.width == 0 {
		_, err := out.WriteString(`[""]`)
		return 1, 0, err
	}

	cells := make([]string, extent.width)
	current, written, filled := 0, 0, 0
	flush := func() error {
		if written > 0 {
			if err := out.WriteByte(','); err != nil {
				return err
			}
		}
		if err := writeJSONRow(out, cells); err != nil {
			return err
		}
		clear(cells)
		written++
		return nil
	}

	err := walkSheet(rr, book, s, func(row, col int, text string) error {
		if row < current || row >= extent.rows || col >= extent.width {
			return nil
		}
		for current < row {
			if err := flush(); err != nil {
				return err
			}
			current++
		}
		if cells[col] == "" {
			filled++
		}
		cells[col] = text
		return nil
	})
	if err != nil {
		return written, filled, err
	}
	for written < extent.rows {
		if err := flush(); err != nil {
			return written, filled, err
		}
	}
	return written, filled, nil
}

// writeJSONRow writes one row as a JSON array of strings.
func writeJSONRow(out *bufio.Writer, cells []string) error {
	if err := out.WriteByte('['); err != nil {
		return err
	}
	for i, cell := range cells {
		if i > 0 {
			if err := out.WriteByte(','); err != nil {
				return err
			}
		}
		if err := writeJSONString(out, cell); err != nil {
			return err
		}
	}
	return out.WriteByte(']')
}

// writeJSONString writes a quoted, escaped JSON string. Cell text is whatever
// the workbook held, control characters included, so it is escaped by the
// JSON encoder rather than by hand.
func writeJSONString(out *bufio.Writer, s string) error {
	encoded, err := json.Marshal(s)
	if err != nil {
		return err
	}
	_, err = out.Write(encoded)
	return err
}
