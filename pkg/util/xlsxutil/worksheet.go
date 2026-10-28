package xlsxutil

import (
	"encoding/xml"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// sheetExtent is how much of a worksheet holds anything: the widest row and
// the last row with content. A worksheet declares a used range of its own, but
// it is written by the producer and often larger than the data, so the extent
// is measured from the cells instead.
type sheetExtent struct {
	width int
	rows  int
}

// measureSheet scans a worksheet for its extent without decoding it.
//
// The editor takes its column count from the first row, so every row has to be
// written the same width, and the width is not known until the last row has
// been read. Measuring in a separate pass is what keeps that from meaning
// "hold the sheet in memory": the pass reads the part a token at a time and
// keeps two integers, and the entry is simply opened again to write from.
func measureSheet(pkg *officezip.Package, name string) (sheetExtent, error) {
	rc, err := openPart(pkg, name, MaxPartBytes)
	if err != nil {
		return sheetExtent{}, err
	}
	defer rc.Close()

	var (
		extent   sheetExtent
		row      int
		col      int
		inCell   bool
		hasValue bool
	)
	dec := xml.NewDecoder(rc)
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return sheetExtent{}, partError(name, err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch t.Name.Local {
			case "row":
				row = attrInt(t, "r", row+1)
			case "c":
				inCell = true
				hasValue = false
				col = cellColumn(attrString(t, "r"), col+1)
			case "v", "t":
				// A cell counts as holding something only once a value with
				// content is seen: Excel writes an empty <c> for every cell
				// that carries formatting alone, and a row of those is not a
				// row of data.
				if inCell && !hasValue {
					hasValue = !nextCharDataIsBlank(dec)
				}
			}
		case xml.EndElement:
			if t.Name.Local == "c" {
				inCell = false
				if hasValue {
					if col > extent.width {
						extent.width = col
					}
					if row > extent.rows {
						extent.rows = row
					}
				}
			}
		}

		if extent.width > MaxColumns {
			return sheetExtent{}, fmt.Errorf("%w: a sheet is wider than %d columns", ErrTooLarge, MaxColumns)
		}
		if extent.rows > MaxRows {
			return sheetExtent{}, fmt.Errorf("%w: a sheet is longer than %d rows", ErrTooLarge, MaxRows)
		}
	}
	return extent, nil
}

// streamSheet decodes a worksheet and hands each row to emit as a slice of
// exactly extent.width cells, for extent.rows rows. Rows and cells a worksheet
// leaves out — it stores only what holds something — are emitted as the empty
// strings they stand for, so a value stays in the column and row it was in.
func streamSheet(pkg *officezip.Package, name string, extent sheetExtent, epoch time.Time, shared []string, formats numberFormats, emit func([]string) error) (int, error) {
	if extent.rows == 0 || extent.width == 0 {
		return 0, nil
	}
	rc, err := openPart(pkg, name, MaxPartBytes)
	if err != nil {
		return 0, err
	}
	defer rc.Close()

	var (
		filled  int
		written int
	)
	dec := xml.NewDecoder(rc)
	for written < extent.rows {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return filled, partError(name, err)
		}
		start, ok := tok.(xml.StartElement)
		if !ok || start.Name.Local != "row" {
			continue
		}

		var row sheetRow
		if err := dec.DecodeElement(&row, &start); err != nil {
			return filled, partError(name, err)
		}
		if row.Index <= 0 {
			row.Index = written + 1
		}

		// Rows the worksheet skipped are empty ones. A row out of order or
		// repeated cannot be gone back to, so it is written where it lands.
		for written < row.Index-1 && written < extent.rows {
			if err := emit(blankRow(extent.width)); err != nil {
				return filled, err
			}
			written++
		}
		if written >= extent.rows {
			break
		}

		cells := make([]string, extent.width)
		col := 0
		for _, cell := range row.Cells {
			col = cellColumn(cell.Ref, col+1)
			if col < 1 || col > extent.width {
				continue
			}
			text := cell.text(shared, formats, epoch)
			if text == "" {
				continue
			}
			cells[col-1] = text
			filled++
		}
		if err := emit(cells); err != nil {
			return filled, err
		}
		written++
	}

	// A worksheet that ends before the extent said it would — a truncated part,
	// or rows declared out of order — still owes the rows it promised.
	for written < extent.rows {
		if err := emit(blankRow(extent.width)); err != nil {
			return filled, err
		}
		written++
	}
	return filled, nil
}

func blankRow(width int) []string {
	return make([]string, width)
}

// text is what a cell displays. The type attribute decides how the stored
// value is read; a number with a date format is the one case where the value
// alone does not say what it means.
func (c sheetCell) text(shared []string, formats numberFormats, epoch time.Time) string {
	switch c.Type {
	case "s":
		// A shared string cell stores an index into the workbook's table.
		if c.Value == nil {
			return ""
		}
		i, err := strconv.Atoi(strings.TrimSpace(*c.Value))
		if err != nil || i < 0 || i >= len(shared) {
			return ""
		}
		return shared[i]

	case "inlineStr":
		if c.Inline == nil {
			return ""
		}
		return c.Inline.text()

	case "b":
		// Excel renders a boolean uppercase, and the editor's own formula
		// language reads TRUE and FALSE the same way.
		if c.Value != nil && strings.TrimSpace(*c.Value) == "1" {
			return "TRUE"
		}
		return "FALSE"

	case "str", "e", "d":
		// A formula's string result, an error such as #DIV/0!, and an ISO-8601
		// date are all already the text the cell shows.
		if c.Value == nil {
			return ""
		}
		return *c.Value
	}

	// No type is a number, which is a date when its format makes it one.
	if c.Value == nil {
		return ""
	}
	raw := strings.TrimSpace(*c.Value)
	if kind := formats.dateKindFor(c.Style); kind != notDate {
		if serial, err := strconv.ParseFloat(raw, 64); err == nil {
			return formatDate(serial, epoch, kind)
		}
	}
	return raw
}

// cellColumn is the 1-based column a cell reference names: the letters of
// "BC7" are base-26 digits, so BC is column 55. A reference that is missing or
// unreadable falls back to fallback, which is the column after the last one —
// where an unlabelled cell sits.
func cellColumn(ref string, fallback int) int {
	col := 0
	for i := 0; i < len(ref); i++ {
		ch := ref[i]
		switch {
		case ch >= 'A' && ch <= 'Z':
			col = col*26 + int(ch-'A') + 1
		case ch >= 'a' && ch <= 'z':
			col = col*26 + int(ch-'a') + 1
		default:
			// The row number ends the column part of the reference.
			if col == 0 || i == 0 {
				return fallback
			}
			return col
		}
		if col > MaxColumns {
			return MaxColumns + 1
		}
	}
	if col == 0 {
		return fallback
	}
	return col
}

// attrInt reads a numeric attribute, falling back when it is absent or not a
// number.
func attrInt(start xml.StartElement, name string, fallback int) int {
	if v := attrString(start, name); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return fallback
}

// attrString reads an attribute by local name, ignoring its namespace.
func attrString(start xml.StartElement, name string) string {
	for _, attr := range start.Attr {
		if attr.Name.Local == name {
			return attr.Value
		}
	}
	return ""
}

// nextCharDataIsBlank reports whether the element just entered holds no text.
// Used by the measuring pass, which needs to know that a cell has content but
// not what the content is.
func nextCharDataIsBlank(dec *xml.Decoder) bool {
	for {
		tok, err := dec.Token()
		if err != nil {
			return true
		}
		switch t := tok.(type) {
		case xml.CharData:
			if strings.TrimSpace(string(t)) != "" {
				return false
			}
		case xml.EndElement:
			return true
		case xml.StartElement:
			// Nested markup inside a value is not text this pass has to read.
			if err := dec.Skip(); err != nil {
				return true
			}
		}
	}
}
