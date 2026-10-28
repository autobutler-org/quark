package xlsxutil

import (
	"encoding/xml"
	"io"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// stylesPart is where a workbook keeps its cell formats.
const stylesPart = "xl/styles.xml"

// builtinDateFormats are the predefined number formats that render a date.
// They carry no format code in the file — a reader is expected to know them —
// so the ones that show a date are listed here by ID.
var builtinDateFormats = map[int]dateKind{
	14: dateOnly,    // mm-dd-yy
	15: dateOnly,    // d-mmm-yy
	16: dateOnly,    // d-mmm
	17: dateOnly,    // mmm-yy
	18: timeOnly,    // h:mm AM/PM
	19: timeOnly,    // h:mm:ss AM/PM
	20: timeOnly,    // h:mm
	21: timeOnly,    // h:mm:ss
	22: dateAndTime, // m/d/yy h:mm
	45: timeOnly,    // mm:ss
	46: timeOnly,    // [h]:mm:ss
	47: timeOnly,    // mmss.0
}

// readStyles loads the cell formats and works out which of them display a
// date. A workbook with no styles part has no date-formatted cells, which is
// not an error — its numbers are all numbers.
func readStyles(pkg *officezip.Package) (numberFormats, error) {
	formats := numberFormats{dateStyles: map[int]dateKind{}}
	if !pkg.Has(stylesPart) {
		return formats, nil
	}
	rc, err := openPart(pkg, stylesPart, MaxPartBytes)
	if err != nil {
		return formats, err
	}
	defer rc.Close()

	// A custom format declares its own code; a builtin is known by ID alone.
	custom := map[int]dateKind{}
	// cellXfs is the list the cells index into, in document order. The same
	// document also carries cellStyleXfs, an unrelated list of the same
	// element name, so only the one inside <cellXfs> is collected.
	var (
		cellXfs   []int
		inCellXfs bool
	)

	dec := xml.NewDecoder(rc)
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return formats, partError(stylesPart, err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch t.Name.Local {
			case "cellXfs":
				inCellXfs = true
			case "numFmt":
				id, code := numFmtAttrs(t)
				if id >= 0 {
					custom[id] = dateKindOf(code)
				}
			case "xf":
				if inCellXfs {
					cellXfs = append(cellXfs, numFmtIDAttr(t))
				}
			}
		case xml.EndElement:
			if t.Name.Local == "cellXfs" {
				inCellXfs = false
			}
		}
	}

	for style, numFmtID := range cellXfs {
		kind, ok := custom[numFmtID]
		if !ok {
			kind = builtinDateFormats[numFmtID]
		}
		if kind != notDate {
			formats.dateStyles[style] = kind
		}
	}
	return formats, nil
}

// numFmtAttrs reads a <numFmt>'s ID and format code, returning -1 for an entry
// whose ID is missing or unparseable.
func numFmtAttrs(start xml.StartElement) (int, string) {
	id := -1
	code := ""
	for _, attr := range start.Attr {
		switch attr.Name.Local {
		case "numFmtId":
			if n, err := strconv.Atoi(attr.Value); err == nil {
				id = n
			}
		case "formatCode":
			code = attr.Value
		}
	}
	return id, code
}

// numFmtIDAttr reads an <xf>'s number format, which is 0 — General — when the
// attribute is absent.
func numFmtIDAttr(start xml.StartElement) int {
	for _, attr := range start.Attr {
		if attr.Name.Local == "numFmtId" {
			if n, err := strconv.Atoi(attr.Value); err == nil {
				return n
			}
		}
	}
	return 0
}

// dateKindOf reads a format code for the date parts it displays. Only its date
// tokens matter, so the literal text a code can carry — quoted runs, escaped
// characters, the color and condition sections in brackets — is stripped
// first. Without that a plain currency format like [$$-409]#,##0.00 reads as a
// date, because its locale tag contains a "d".
func dateKindOf(code string) dateKind {
	stripped := stripFormatLiterals(code)
	// A format's sections are separated by semicolons and describe the same
	// value for positive, negative and zero; the first is enough.
	if i := strings.IndexByte(stripped, ';'); i >= 0 {
		stripped = stripped[:i]
	}

	var day, clock bool
	for _, r := range strings.ToLower(stripped) {
		switch r {
		case 'y', 'd':
			day = true
		case 'h':
			clock = true
		case 'm':
			// "m" is minutes next to an hour and months everywhere else.
			// Either way the format shows a date part, and which one it is
			// decides nothing here: a lone "m" format is a month, and one
			// beside an "h" is covered by the clock flag it sets.
			day = true
		case 's':
			clock = true
		}
	}

	switch {
	case day && clock:
		return dateAndTime
	case day:
		return dateOnly
	case clock:
		return timeOnly
	}
	return notDate
}

// stripFormatLiterals removes the parts of a number format code that are text
// rather than a placeholder: quoted runs, backslash-escaped characters, and
// the bracketed color, condition and locale sections.
func stripFormatLiterals(code string) string {
	var b strings.Builder
	for i := 0; i < len(code); i++ {
		switch code[i] {
		case '"':
			i = skipPast(code, i+1, '"')
		case '[':
			i = skipPast(code, i+1, ']')
		case '\\':
			i++ // the escaped character is a literal, not a placeholder
		default:
			b.WriteByte(code[i])
		}
	}
	return b.String()
}

// skipPast is the index of the next closer at or after start, or the end of
// the string when the literal was never closed.
func skipPast(s string, start int, closer byte) int {
	if start >= len(s) {
		return len(s)
	}
	if i := strings.IndexByte(s[start:], closer); i >= 0 {
		return start + i
	}
	return len(s)
}

// dateKindFor says how a cell's style renders its number. A cell with no style
// has no format, so it is a number.
func (f numberFormats) dateKindFor(style *int) dateKind {
	if style == nil {
		return notDate
	}
	return f.dateStyles[*style]
}

// formatDate renders a date serial as the date it denotes. Excel counts whole
// days from the workbook's epoch, and the fraction is the time of day.
func formatDate(serial float64, epoch time.Time, kind dateKind) string {
	days := math.Floor(serial)
	// Rounded to the second: the fraction is a binary approximation of the
	// time of day, so 12:00:00 arrives as 0.4999999999 as often as not.
	seconds := math.Round((serial - days) * 24 * 60 * 60)
	t := epoch.AddDate(0, 0, int(days)).Add(time.Duration(seconds) * time.Second)

	switch kind {
	case dateOnly:
		return t.Format("2006-01-02")
	case timeOnly:
		return t.Format("15:04:05")
	default:
		return t.Format("2006-01-02 15:04:05")
	}
}
