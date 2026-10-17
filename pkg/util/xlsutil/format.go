package xlsutil

// cspell:ignore DATEMODE

import (
	"encoding/binary"
	"math"
	"strconv"
	"strings"
	"time"
)

// excelEpoch is the day serial 0 denotes under the 1900 date system. It is
// 1899-12-30 rather than 1899-12-31 because Excel counts a 29th of February
// 1900 that never happened, and every serial after it inherits the extra day.
var excelEpoch = time.Date(1899, time.December, 30, 0, 0, 0, 0, time.UTC)

// excelEpoch1904 is the same for a workbook saved with the 1904 date system
// (DATEMODE 1), which has no phantom leap day to correct for.
var excelEpoch1904 = time.Date(1904, time.January, 1, 0, 0, 0, 0, time.UTC)

// maxDateSerial is the first serial past 9999-12-31, the last date Excel
// shows. A larger number in a date format is shown as the number it is.
const maxDateSerial = 2_958_466

// builtinDateFormats are the predefined number formats that render a date.
// They carry no FORMAT record — a reader is expected to know them — so the
// ones that show a date are listed by ID. 27–36 and 50–58 are the East Asian
// locales' date formats, which BIFF8 numbers in the same table.
var builtinDateFormats = map[int]dateKind{
	14: dateOnly, 15: dateOnly, 16: dateOnly, 17: dateOnly,
	18: timeOnly, 19: timeOnly, 20: timeOnly, 21: timeOnly,
	22: dateAndTime,
	27: dateOnly, 28: dateOnly, 29: dateOnly, 30: dateOnly, 31: dateOnly,
	32: timeOnly, 33: timeOnly, 34: timeOnly, 35: timeOnly, 36: dateOnly,
	45: timeOnly, 46: timeOnly, 47: timeOnly,
	50: dateOnly, 51: dateOnly, 52: dateOnly, 53: dateOnly, 54: dateOnly,
	55: dateOnly, 56: dateOnly, 57: dateOnly, 58: dateOnly,
}

// errorCodes are the BOOLERR and FORMULA error values, as Excel shows them.
var errorCodes = map[byte]string{
	0x00: "#NULL!",
	0x07: "#DIV/0!",
	0x0F: "#VALUE!",
	0x17: "#REF!",
	0x1D: "#NAME?",
	0x24: "#NUM!",
	0x2A: "#N/A",
}

// numberText is what a number cell displays: the date it denotes when its
// XF's format is a date format, and otherwise the number as stored.
func (book *workbook) numberText(v float64, xf int) string {
	if xf >= 0 && xf < len(book.xfDates) {
		if kind := book.xfDates[xf]; kind != notDate && v >= 0 && v < maxDateSerial {
			return formatDate(v, book.epoch, kind)
		}
	}
	return formatNumber(v)
}

// formatNumber writes a double the way a spreadsheet stores it as text: the
// shortest digits that read back as the same value, in plain notation unless
// the magnitude makes that absurd.
func formatNumber(v float64) string {
	if v == 0 {
		return "0" // and never "-0"
	}
	if abs := math.Abs(v); abs >= 1e-6 && abs < 1e21 {
		return strconv.FormatFloat(v, 'f', -1, 64)
	}
	return strconv.FormatFloat(v, 'g', -1, 64)
}

// formatDate renders a date serial as the date it denotes. Excel counts whole
// days from the workbook's epoch, and the fraction is the time of day. The
// output is the same as xlsxutil's for the same cell.
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

// rkNumber decodes an RK value: a 30-bit integer or the top 30 bits of a
// double, either one optionally scaled by 1/100.
func rkNumber(rk uint32) float64 {
	var v float64
	if rk&0x02 != 0 {
		v = float64(int32(rk) >> 2)
	} else {
		v = math.Float64frombits(uint64(rk&0xFFFFFFFC) << 32)
	}
	if rk&0x01 != 0 {
		v /= 100
	}
	return v
}

// float64At reads a little-endian IEEE double.
func float64At(b []byte) float64 {
	return math.Float64frombits(binary.LittleEndian.Uint64(b))
}

// dateKindOf reads a format code for the date parts it displays. Only its
// date tokens matter, so the literal text a code can carry — quoted runs,
// escaped characters, the color and condition sections in brackets — is
// stripped first. Without that a plain currency format like [$$-409]#,##0.00
// reads as a date, because its locale tag contains a "d".
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
		case 'y', 'd', 'm':
			// "m" is minutes next to an hour and months everywhere else.
			// Either way the format shows a date part; a lone "m" is a month,
			// and one beside an "h" is covered by the clock flag it sets.
			day = true
		case 'h', 's':
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
