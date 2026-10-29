package xlsxutil

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
)

// writeQsheet writes the .qsheet envelope for a workbook, one tab per
// worksheet, streaming each row onto w as it is read rather than building the
// document and then writing it.
func writeQsheet(w io.Writer, book workbook, shared []string, formats numberFormats) (ConvertToQsheetResult, error) {
	var result ConvertToQsheetResult

	out := bufio.NewWriter(w)
	if _, err := out.WriteString(`{"tabs":[`); err != nil {
		return result, err
	}

	for i, sheet := range book.sheets {
		extent, err := measureSheet(book.pkg, sheet.part)
		if err != nil {
			return result, err
		}
		if result.Rows+extent.rows > MaxRows {
			return result, fmt.Errorf("%w: the workbook holds more than %d rows", ErrTooLarge, MaxRows)
		}
		if result.Cells+extent.rows*extent.width > MaxCells {
			return result, fmt.Errorf("%w: the workbook holds more than %d cells", ErrTooLarge, MaxCells)
		}

		if i > 0 {
			if err := out.WriteByte(','); err != nil {
				return result, err
			}
		}
		if _, err := out.WriteString(`{"name":`); err != nil {
			return result, err
		}
		if err := writeJSONString(out, sheet.name); err != nil {
			return result, err
		}
		if _, err := out.WriteString(`,"data":{"rows":[`); err != nil {
			return result, err
		}

		// The editor treats a sheet with no rows as a broken document and
		// replaces it with a blank one; an empty worksheet is written as the
		// single empty row that means the same thing.
		if extent.rows == 0 || extent.width == 0 {
			if _, err := out.WriteString(`[""]`); err != nil {
				return result, err
			}
			result.Rows++
		}

		rows := 0
		filled, err := streamSheet(book.pkg, sheet.part, extent, book.epoch, shared, formats, func(cells []string) error {
			if rows > 0 {
				if err := out.WriteByte(','); err != nil {
					return err
				}
			}
			rows++
			return writeJSONRow(out, cells)
		})
		if err != nil {
			return result, err
		}

		if _, err := out.WriteString(`]}}`); err != nil {
			return result, err
		}
		result.Tabs++
		result.Rows += rows
		result.Cells += filled
	}

	if _, err := out.WriteString(`]}`); err != nil {
		return result, err
	}
	return result, out.Flush()
}

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
// the workbook held — quotes, backslashes, control characters and invalid
// UTF-8 included — so it is escaped by the JSON encoder rather than by hand.
func writeJSONString(out *bufio.Writer, s string) error {
	encoded, err := json.Marshal(s)
	if err != nil {
		return err
	}
	_, err = out.Write(encoded)
	return err
}
