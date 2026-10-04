package xlsxutil

import (
	"archive/zip"
	"bufio"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// The namespaces and content types every package part below declares.
const (
	nsMain          = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
	nsRelationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
	nsPackageRels   = "http://schemas.openxmlformats.org/package/2006/relationships"
	xmlHeader       = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n"
	// maxCellText is Excel's limit on one cell's text; a longer cell makes
	// Excel offer to repair the whole workbook.
	maxCellText = 32_767
	// maxSheetName is Excel's limit on a worksheet name.
	maxSheetName = 31
	// maxNumberDigits is the precision Excel keeps. A longer run of digits — a
	// card or account number — is an identifier, and stays text so it is not
	// rounded.
	maxNumberDigits = 15
	// pixelsPerChar converts the editor's pixel column widths into Excel's
	// width unit, the width of one digit in the default font.
	pixelsPerChar = 7.0
)

// plainNumber is the cell text written as a number: an optional minus, digits
// with no leading zero (a zip code keeps its zero as text), an optional
// fraction and exponent. Anything ParseFloat would also accept beyond this —
// hex, "Inf", underscores — stays text.
var plainNumber = regexp.MustCompile(`^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$`)

// writeXlsx streams the .qsheet in src onto w as a workbook. Each tab is
// decoded whole and written as its worksheet part before the next is read;
// the parts that list every sheet and style are written last.
func writeXlsx(w io.Writer, src io.Reader) (ExportQsheetResult, error) {
	var result ExportQsheetResult
	zw := zip.NewWriter(w)
	styles := newStyleTable()
	var names []string

	dec := json.NewDecoder(src)
	dec.UseNumber()
	err := walkTabs(dec, func(tab qsheetTab) error {
		if len(names) == MaxSheets {
			return fmt.Errorf("%w: the sheet holds more than %d tabs", ErrTooLarge, MaxSheets)
		}
		names = append(names, uniqueSheetName(tab.Name, len(names), names))
		return writeWorksheet(zw, len(names), tab, styles, &result)
	})
	if err != nil {
		return result, err
	}
	// A workbook needs at least one sheet, and the editor opens a document
	// with no tabs as one blank one.
	if len(names) == 0 {
		names = append(names, "Sheet1")
		if err := writeWorksheet(zw, 1, qsheetTab{}, styles, &result); err != nil {
			return result, err
		}
	}

	parts := []struct {
		name string
		body string
	}{
		{"xl/workbook.xml", workbookPart(names)},
		{"xl/_rels/workbook.xml.rels", workbookRelsPart(len(names))},
		{"xl/styles.xml", styles.part()},
		{"_rels/.rels", xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">` +
			`<Relationship Id="rId1" Type="` + nsRelationships + `/officeDocument" Target="xl/workbook.xml"/>` +
			`</Relationships>`},
		{"[Content_Types].xml", contentTypesPart(len(names))},
	}
	for _, part := range parts {
		f, err := zw.Create(part.name)
		if err != nil {
			return result, err
		}
		if _, err := io.WriteString(f, part.body); err != nil {
			return result, err
		}
	}
	return result, zw.Close()
}

// walkTabs steps through the envelope's top-level object and hands each entry
// of "tabs" to emit, decoded one at a time. Other keys are skipped.
func walkTabs(dec *json.Decoder, emit func(qsheetTab) error) error {
	if err := expectDelim(dec, '{'); err != nil {
		return err
	}
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return qsheetError(err)
		}
		if key != "tabs" {
			var skip json.RawMessage
			if err := dec.Decode(&skip); err != nil {
				return qsheetError(err)
			}
			continue
		}
		if err := expectDelim(dec, '['); err != nil {
			return err
		}
		for dec.More() {
			var tab qsheetTab
			if err := dec.Decode(&tab); err != nil {
				return qsheetError(err)
			}
			if err := emit(tab); err != nil {
				return err
			}
		}
		if err := expectDelim(dec, ']'); err != nil {
			return err
		}
	}
	return expectDelim(dec, '}')
}

// expectDelim reads the next token and fails unless it is want.
func expectDelim(dec *json.Decoder, want json.Delim) error {
	tok, err := dec.Token()
	if err != nil {
		return qsheetError(err)
	}
	if tok != want {
		return fmt.Errorf("%w: expected %q", ErrNotQsheet, want)
	}
	return nil
}

// qsheetError tells a source past [MaxQsheetBytes], which the cappedReader
// reports through the decoder, from one that is not JSON at all.
func qsheetError(err error) error {
	if errors.Is(err, ErrTooLarge) {
		return err
	}
	return fmt.Errorf("%w: %v", ErrNotQsheet, err)
}

func (c *cappedReader) Read(p []byte) (int, error) {
	if c.remaining <= 0 {
		// One byte past the cap is what tells a document that is too large
		// from one that fills it exactly.
		var probe [1]byte
		if n, _ := c.r.Read(probe[:]); n > 0 {
			return 0, fmt.Errorf("%w: the sheet is larger than %d bytes", ErrTooLarge, MaxQsheetBytes)
		}
		return 0, io.EOF
	}
	if int64(len(p)) > c.remaining {
		p = p[:c.remaining]
	}
	n, err := c.r.Read(p)
	c.remaining -= int64(n)
	return n, err
}

// writeWorksheet writes tab as worksheet part number index (1-based) and adds
// what it wrote to result.
func writeWorksheet(zw *zip.Writer, index int, tab qsheetTab, styles *styleTable, result *ExportQsheetResult) error {
	rows := tab.Data.Rows
	width := 0
	for _, row := range rows {
		width = max(width, len(row))
	}
	if width > MaxColumns {
		return fmt.Errorf("%w: a tab holds more than %d columns", ErrTooLarge, MaxColumns)
	}
	if result.Rows+len(rows) > MaxRows {
		return fmt.Errorf("%w: the sheet holds more than %d rows", ErrTooLarge, MaxRows)
	}
	if result.Cells+len(rows)*width > MaxCells {
		return fmt.Errorf("%w: the sheet holds more than %d cells", ErrTooLarge, MaxCells)
	}

	cellStyles := make(map[[2]int]int, len(tab.Formats))
	for _, f := range tab.Formats {
		if f.Row >= 0 && f.Row < len(rows) && f.Col >= 0 && f.Col < width {
			if xf := styles.add(f); xf > 0 {
				cellStyles[[2]int{f.Row, f.Col}] = xf
			}
		}
	}

	part, err := zw.Create(fmt.Sprintf("xl/worksheets/sheet%d.xml", index))
	if err != nil {
		return err
	}
	out := partWriter{bufio.NewWriter(part)}
	out.put(xmlHeader + `<worksheet xmlns="` + nsMain + `">`)
	out.put(sheetView(tab.FrozenRows, tab.FrozenColumns))
	writeColumns(out, tab.ColumnWidths)
	out.put(`<sheetData>`)

	for r, row := range rows {
		opened := false
		for c := range width {
			text := ""
			if c < len(row) {
				text = cellText(row[c])
			}
			xf, styled := cellStyles[[2]int{r, c}]
			if text == "" && !styled {
				continue
			}
			if !opened {
				out.printf(`<row r="%d">`, r+1)
				opened = true
			}
			writeCell(out, columnName(c)+strconv.Itoa(r+1), text, xf)
			if text != "" {
				result.Cells++
			}
		}
		if opened {
			out.put(`</row>`)
		}
	}

	// partWriter keeps the first write error for Flush to report.
	out.put(`</sheetData></worksheet>`)
	if err := out.Flush(); err != nil {
		return err
	}
	result.Tabs++
	result.Rows += len(rows)
	return nil
}

// cellText is a decoded JSON cell as the editor reads it: the editor stores
// strings, but reads any scalar by its text.
func cellText(v any) string {
	switch v := v.(type) {
	case string:
		return v
	case json.Number:
		return v.String()
	case bool:
		return strconv.FormatBool(v)
	case nil:
		return ""
	}
	return fmt.Sprint(v)
}

// writeCell writes one <c>: a number when the text is a plain one, text
// otherwise. Formulas are text — see [ExportQsheet].
func writeCell(out partWriter, ref, text string, xf int) {
	out.put(`<c r="` + ref + `"`)
	if xf > 0 {
		out.printf(` s="%d"`, xf)
	}
	switch {
	case text == "":
		out.put(`/>`)
	case isPlainNumber(text):
		out.put(`><v>` + text + `</v></c>`)
	default:
		out.put(` t="inlineStr"><is><t xml:space="preserve">`)
		escape(out, truncateRunes(text, maxCellText))
		out.put(`</t></is></c>`)
	}
}

// isPlainNumber reports whether text is written as a number.
func isPlainNumber(text string) bool {
	if !plainNumber.MatchString(text) {
		return false
	}
	mantissa, _, _ := strings.Cut(strings.ToLower(text), "e")
	digits := 0
	for _, r := range mantissa {
		if r >= '0' && r <= '9' {
			digits++
		}
	}
	if digits > maxNumberDigits {
		return false
	}
	f, err := strconv.ParseFloat(text, 64)
	return err == nil && !math.IsInf(f, 0)
}

// sheetView freezes the first rows and columns, as the editor does.
func sheetView(rows, cols int) string {
	rows = max(rows, 0)
	cols = max(cols, 0)
	if rows == 0 && cols == 0 {
		return `<sheetViews><sheetView workbookViewId="0"/></sheetViews>`
	}
	pane := "bottomRight"
	switch {
	case cols == 0:
		pane = "bottomLeft"
	case rows == 0:
		pane = "topRight"
	}
	var b strings.Builder
	b.WriteString(`<sheetViews><sheetView workbookViewId="0"><pane`)
	if cols > 0 {
		fmt.Fprintf(&b, ` xSplit="%d"`, cols)
	}
	if rows > 0 {
		fmt.Fprintf(&b, ` ySplit="%d"`, rows)
	}
	fmt.Fprintf(&b, ` topLeftCell="%s%d" activePane="%s" state="frozen"/></sheetView></sheetViews>`,
		columnName(cols), rows+1, pane)
	return b.String()
}

// writeColumns writes the editor's column widths, converted from pixels.
func writeColumns(out partWriter, widths []float64) {
	if len(widths) == 0 || len(widths) > MaxColumns {
		return
	}
	out.put(`<cols>`)
	for i, px := range widths {
		if math.IsNaN(px) || math.IsInf(px, 0) || px <= 0 {
			continue
		}
		out.printf(`<col min="%d" max="%d" width="%.2f" customWidth="1"/>`,
			i+1, i+1, math.Min(px/pixelsPerChar, 255))
	}
	out.put(`</cols>`)
}

// columnName is the letters of a zero-based column: 0 is A, 26 is AA.
func columnName(col int) string {
	var b []byte
	for col++; col > 0; col = (col - 1) / 26 {
		b = append([]byte{byte('A' + (col-1)%26)}, b...)
	}
	return string(b)
}

// escape writes s as XML character data. EscapeText also escapes quotes, so
// the same call serves attribute values, and replaces the control characters
// XML cannot carry.
func escape(out io.Writer, s string) {
	// The writers here are a partWriter or a strings.Builder: the first keeps
	// its error for the caller's Flush, and the second cannot fail.
	_ = xml.EscapeText(out, []byte(s))
}

// truncateRunes cuts s to at most limit runes.
func truncateRunes(s string, limit int) string {
	if utf8.RuneCountInString(s) <= limit {
		return s
	}
	return string([]rune(s)[:limit])
}

// uniqueSheetName makes name a worksheet name Excel accepts: none of the
// characters it forbids, at most 31 characters, not blank, and unlike every
// name in taken regardless of case. index is the tab's zero-based position,
// for the name a blank one gets.
func uniqueSheetName(name string, index int, taken []string) string {
	name = strings.Map(func(r rune) rune {
		if strings.ContainsRune(`[]:*?/\`, r) || r < 0x20 {
			return '_'
		}
		return r
	}, name)
	name = strings.Trim(strings.TrimSpace(name), "'")
	if name == "" || strings.EqualFold(name, "History") {
		name = fmt.Sprintf("Sheet%d", index+1)
	}
	name = truncateRunes(name, maxSheetName)
	candidate := name
	for n := 2; nameTaken(candidate, taken); n++ {
		suffix := fmt.Sprintf(" (%d)", n)
		candidate = truncateRunes(name, maxSheetName-len(suffix)) + suffix
	}
	return candidate
}

func nameTaken(name string, taken []string) bool {
	for _, t := range taken {
		if strings.EqualFold(t, name) {
			return true
		}
	}
	return false
}

// workbookPart lists the worksheets in tab order.
func workbookPart(names []string) string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<workbook xmlns="` + nsMain + `" xmlns:r="` + nsRelationships + `">`)
	b.WriteString(`<bookViews><workbookView/></bookViews><sheets>`)
	for i, name := range names {
		b.WriteString(`<sheet name="`)
		escape(&b, name)
		fmt.Fprintf(&b, `" sheetId="%d" r:id="rId%d"/>`, i+1, i+1)
	}
	b.WriteString(`</sheets></workbook>`)
	return b.String()
}

// workbookRelsPart points rId1..count at the worksheets, and the next one at
// the styles.
func workbookRelsPart(count int) string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">`)
	for i := 1; i <= count; i++ {
		fmt.Fprintf(&b, `<Relationship Id="rId%d" Type="%s/worksheet" Target="worksheets/sheet%d.xml"/>`,
			i, nsRelationships, i)
	}
	fmt.Fprintf(&b, `<Relationship Id="rId%d" Type="%s/styles" Target="styles.xml"/>`, count+1, nsRelationships)
	b.WriteString(`</Relationships>`)
	return b.String()
}

// contentTypesPart declares the type of every part in the package.
func contentTypesPart(count int) string {
	const ct = "application/vnd.openxmlformats-officedocument.spreadsheetml"
	var b strings.Builder
	b.WriteString(xmlHeader + `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">`)
	b.WriteString(`<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>`)
	b.WriteString(`<Default Extension="xml" ContentType="application/xml"/>`)
	b.WriteString(`<Override PartName="/xl/workbook.xml" ContentType="` + ct + `.sheet.main+xml"/>`)
	for i := 1; i <= count; i++ {
		fmt.Fprintf(&b, `<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="%s.worksheet+xml"/>`, i, ct)
	}
	b.WriteString(`<Override PartName="/xl/styles.xml" ContentType="` + ct + `.styles+xml"/>`)
	b.WriteString(`</Types>`)
	return b.String()
}

// newStyleTable starts the tables with the defaults a workbook must carry:
// the default font, the two fills Excel reserves, and the plain cell format.
func newStyleTable() *styleTable {
	return &styleTable{
		xfs:     []cellStyle{{}},
		xfIndex: map[cellStyle]int{{}: 0},
		fonts:   []font{{}},
		fontIdx: map[font]int{{}: 0},
		fills:   []string{"none", "gray125"},
		fillIdx: map[string]int{},
		fmtIdx:  map[string]int{},
	}
}

// add returns the cellXfs index for f's style, adding it the first time it is
// seen. A format that changes nothing a workbook stores is index 0.
func (s *styleTable) add(f qsheetFormat) int {
	style := cellStyle{
		bold:      f.Bold,
		italic:    f.Italic,
		textColor: argbHex(f.TextColor),
		fillColor: argbHex(f.FillColor),
		numFmt:    numberFormatCode(f.NumberFormat, f.Decimals),
	}
	switch f.Align {
	case "left", "center", "right":
		style.align = f.Align
	}
	if i, ok := s.xfIndex[style]; ok {
		return i
	}
	s.xfIndex[style] = len(s.xfs)
	s.xfs = append(s.xfs, style)
	if fn := (font{style.bold, style.italic, style.textColor}); fn != (font{}) {
		if _, ok := s.fontIdx[fn]; !ok {
			s.fontIdx[fn] = len(s.fonts)
			s.fonts = append(s.fonts, fn)
		}
	}
	if style.fillColor != "" {
		if _, ok := s.fillIdx[style.fillColor]; !ok {
			s.fillIdx[style.fillColor] = len(s.fills)
			s.fills = append(s.fills, style.fillColor)
		}
	}
	if style.numFmt != "" {
		if _, ok := s.fmtIdx[style.numFmt]; !ok {
			// Custom number formats are numbered from 164; below that are
			// Excel's built-in ones.
			s.fmtIdx[style.numFmt] = 164 + len(s.numFmts)
			s.numFmts = append(s.numFmts, style.numFmt)
		}
	}
	return s.xfIndex[style]
}

// part is styles.xml for every style added.
func (s *styleTable) part() string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<styleSheet xmlns="` + nsMain + `">`)
	if len(s.numFmts) > 0 {
		fmt.Fprintf(&b, `<numFmts count="%d">`, len(s.numFmts))
		for _, code := range s.numFmts {
			fmt.Fprintf(&b, `<numFmt numFmtId="%d" formatCode="`, s.fmtIdx[code])
			escape(&b, code)
			b.WriteString(`"/>`)
		}
		b.WriteString(`</numFmts>`)
	}

	fmt.Fprintf(&b, `<fonts count="%d">`, len(s.fonts))
	for _, f := range s.fonts {
		b.WriteString(`<font>`)
		if f.bold {
			b.WriteString(`<b/>`)
		}
		if f.italic {
			b.WriteString(`<i/>`)
		}
		b.WriteString(`<sz val="11"/>`)
		if f.color != "" {
			b.WriteString(`<color rgb="` + f.color + `"/>`)
		}
		b.WriteString(`<name val="Calibri"/><family val="2"/></font>`)
	}
	b.WriteString(`</fonts>`)

	fmt.Fprintf(&b, `<fills count="%d">`, len(s.fills))
	for i, fill := range s.fills {
		if i < 2 {
			b.WriteString(`<fill><patternFill patternType="` + fill + `"/></fill>`)
			continue
		}
		b.WriteString(`<fill><patternFill patternType="solid"><fgColor rgb="` + fill + `"/><bgColor indexed="64"/></patternFill></fill>`)
	}
	b.WriteString(`</fills>`)

	b.WriteString(`<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>`)
	b.WriteString(`<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>`)

	fmt.Fprintf(&b, `<cellXfs count="%d">`, len(s.xfs))
	for _, style := range s.xfs {
		numFmt := s.fmtIdx[style.numFmt]
		fontID := s.fontIdx[font{style.bold, style.italic, style.textColor}]
		fillID := s.fillIdx[style.fillColor]
		fmt.Fprintf(&b, `<xf numFmtId="%d" fontId="%d" fillId="%d" borderId="0" xfId="0"`, numFmt, fontID, fillID)
		for _, apply := range []struct {
			name string
			on   bool
		}{
			{"applyNumberFormat", numFmt > 0},
			{"applyFont", fontID > 0},
			{"applyFill", fillID > 0},
			{"applyAlignment", style.align != ""},
		} {
			if apply.on {
				b.WriteString(` ` + apply.name + `="1"`)
			}
		}
		if style.align == "" {
			b.WriteString(`/>`)
			continue
		}
		b.WriteString(`><alignment horizontal="` + style.align + `"/></xf>`)
	}
	b.WriteString(`</cellXfs>`)
	b.WriteString(`<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>`)
	b.WriteString(`</styleSheet>`)
	return b.String()
}

// argbHex is the editor's 32-bit ARGB color in the AARRGGBB form a workbook
// stores, or "" for no color.
func argbHex(argb *int64) string {
	if argb == nil {
		return ""
	}
	return fmt.Sprintf("%08X", uint32(*argb))
}

// numberFormatCode is the Excel format code for one of the editor's number
// formats, showing the same decimals, or "" for general.
func numberFormatCode(format string, decimals *int) string {
	places := 2
	if decimals != nil {
		places = min(max(*decimals, 0), 10)
	}
	fraction := ""
	if places > 0 {
		fraction = "." + strings.Repeat("0", places)
	}
	switch format {
	case "number":
		return "#,##0" + fraction
	case "currency":
		return `"$"#,##0` + fraction
	case "percent":
		return "#,##0" + fraction + "%"
	case "date":
		return "yyyy-mm-dd"
	}
	return ""
}

// put writes s. A failure is kept by the bufio.Writer and reported by Flush.
func (w partWriter) put(s string) { _, _ = w.WriteString(s) }

// printf writes a formatted string, its failure kept for Flush as put's is.
func (w partWriter) printf(format string, args ...any) { _, _ = fmt.Fprintf(w.Writer, format, args...) }
