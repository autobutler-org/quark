package xlsxutil

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
)

// buildXlsx packages the given parts as a zip and returns it with its size,
// which is what ConvertToQsheet takes.
func buildXlsx(t *testing.T, parts map[string]string) (*bytes.Reader, int64) {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range parts {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatalf("create %s: %v", name, err)
		}
		if _, err := w.Write([]byte(body)); err != nil {
			t.Fatalf("write %s: %v", name, err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close zip: %v", err)
	}
	return bytes.NewReader(buf.Bytes()), int64(buf.Len())
}

// rootRels is the package relationship naming the workbook.
const rootRels = `<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`

// workbookXML declares the named sheets in order.
func workbookXML(names ...string) string {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0"?><workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>`)
	for i, name := range names {
		fmt.Fprintf(&b, `<sheet name="%s" sheetId="%d" r:id="rId%d"/>`, name, i+1, i+1)
	}
	b.WriteString(`</sheets></workbook>`)
	return b.String()
}

// workbookRels points each sheet relationship at its worksheet part.
func workbookRels(count int) string {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`)
	for i := 1; i <= count; i++ {
		fmt.Fprintf(&b,
			`<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>`,
			i, i)
	}
	b.WriteString(`</Relationships>`)
	return b.String()
}

// sheetXML wraps rows in the worksheet envelope.
func sheetXML(rows string) string {
	return `<?xml version="1.0"?><worksheet><sheetData>` + rows + `</sheetData></worksheet>`
}

// convert runs the conversion and returns the decoded envelope.
func convert(t *testing.T, parts map[string]string) qsheetDoc {
	t.Helper()
	src, size := buildXlsx(t, parts)
	var out bytes.Buffer
	if _, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &out}); err != nil {
		t.Fatalf("ConvertToQsheet: %v", err)
	}
	var doc qsheetDoc
	if err := json.Unmarshal(out.Bytes(), &doc); err != nil {
		t.Fatalf("envelope is not valid JSON: %v\n%s", err, out.String())
	}
	return doc
}

// qsheetDoc is the envelope the editor reads, decoded back for assertions.
type qsheetDoc struct {
	Tabs []struct {
		Name string `json:"name"`
		Data struct {
			Rows [][]string `json:"rows"`
		} `json:"data"`
	} `json:"tabs"`
}

func TestConvertToQsheetCellTypes(t *testing.T) {
	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Budget"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/sharedStrings.xml":       `<sst><si><t>Item</t></si><si><t>Cost</t></si><si><r><t>Rich</t></r><r><t> Text</t></r></si></sst>`,
		"xl/worksheets/sheet1.xml": sheetXML(
			`<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>` +
				`<row r="2"><c r="A2" t="inlineStr"><is><t>Coffee</t></is></c><c r="B2"><v>4.5</v></c></row>` +
				`<row r="3"><c r="A3" t="s"><v>2</v></c><c r="B3"><f>B2*2</f><v>9</v></c></row>` +
				`<row r="4"><c r="A4" t="b"><v>1</v></c><c r="B4" t="e"><v>#DIV/0!</v></c></row>`),
	})

	if len(doc.Tabs) != 1 {
		t.Fatalf("got %d tabs, want 1", len(doc.Tabs))
	}
	if doc.Tabs[0].Name != "Budget" {
		t.Errorf("tab name = %q, want %q", doc.Tabs[0].Name, "Budget")
	}
	want := [][]string{
		{"Item", "Cost"},
		{"Coffee", "4.5"},
		{"Rich Text", "9"}, // a formula contributes its cached result
		{"TRUE", "#DIV/0!"},
	}
	assertRows(t, doc.Tabs[0].Data.Rows, want)
}

func TestConvertToQsheetFillsGaps(t *testing.T) {
	// Row 2 and column B hold nothing, and neither is stored. Both have to
	// come back so the values below and to the right stay where they were.
	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Sheet1"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/worksheets/sheet1.xml": sheetXML(
			`<row r="1"><c r="A1"><v>1</v></c></row>` +
				`<row r="3"><c r="C3"><v>3</v></c></row>`),
	})

	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{
		{"1", "", ""},
		{"", "", ""},
		{"", "", "3"},
	})
}

func TestConvertToQsheetTrimsTrailingBlanks(t *testing.T) {
	// Cells that carry formatting but no value are not data: the sheet is one
	// row of one column, not five rows of four.
	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Sheet1"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/worksheets/sheet1.xml": sheetXML(
			`<row r="1"><c r="A1"><v>1</v></c><c r="B1" s="4"/><c r="D1" s="4"><v></v></c></row>` +
				`<row r="5"><c r="D5" s="4"/></row>`),
	})

	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{{"1"}})
}

func TestConvertToQsheetMultipleSheets(t *testing.T) {
	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("First", "Second"),
		"xl/_rels/workbook.xml.rels": workbookRels(2),
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="A1"><v>1</v></c></row>`),
		"xl/worksheets/sheet2.xml":   sheetXML(`<row r="1"><c r="A1"><v>2</v></c></row>`),
	})

	if len(doc.Tabs) != 2 {
		t.Fatalf("got %d tabs, want 2", len(doc.Tabs))
	}
	if doc.Tabs[0].Name != "First" || doc.Tabs[1].Name != "Second" {
		t.Errorf("tab names = %q, %q; want First, Second", doc.Tabs[0].Name, doc.Tabs[1].Name)
	}
	assertRows(t, doc.Tabs[1].Data.Rows, [][]string{{"2"}})
}

func TestConvertToQsheetEmptySheetKeepsARow(t *testing.T) {
	// The editor replaces a tab with no rows with a blank one, so an empty
	// worksheet is written as the empty row that already means that.
	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Empty"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/worksheets/sheet1.xml":   sheetXML(``),
	})

	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{{""}})
}

func TestConvertToQsheetDates(t *testing.T) {
	// numFmtId 14 is the builtin short date; 164 and up are the workbook's own
	// codes. The last two are the regression: a color section and a quoted
	// suffix are literal text, but both spell date letters ("Red", "days"), so
	// a reader that scans the raw code calls a plain number a date. See
	// stripFormatLiterals.
	styles := `<styleSheet>
	  <numFmts>
	    <numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm:ss"/>
	    <numFmt numFmtId="165" formatCode="#,##0.00;[Red]-#,##0.00"/>
	    <numFmt numFmtId="166" formatCode="0&quot; days&quot;"/>
	  </numFmts>
	  <cellXfs>
	    <xf numFmtId="0"/>
	    <xf numFmtId="14"/>
	    <xf numFmtId="164"/>
	    <xf numFmtId="165"/>
	    <xf numFmtId="21"/>
	    <xf numFmtId="166"/>
	  </cellXfs>
	</styleSheet>`

	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Dates"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/styles.xml":              styles,
		"xl/worksheets/sheet1.xml": sheetXML(
			`<row r="1">` +
				`<c r="A1" s="1"><v>45000</v></c>` +
				`<c r="B1" s="2"><v>45000.5</v></c>` +
				`<c r="C1" s="3"><v>45000</v></c>` +
				`<c r="D1" s="4"><v>0.25</v></c>` +
				`<c r="E1" s="0"><v>45000</v></c>` +
				`<c r="F1" s="5"><v>45000</v></c>` +
				`</row>`),
	})

	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{{
		"2023-03-15",          // builtin date format
		"2023-03-15 12:00:00", // custom date-and-time format
		"45000",               // a [Red] color section, not a date
		"06:00:00",            // builtin time format
		"45000",               // General, not a date
		"45000",               // a quoted " days" suffix, not a date
	}})
}

func TestConvertToQsheet1904Dates(t *testing.T) {
	doc := convert(t, map[string]string{
		"_rels/.rels": rootRels,
		"xl/workbook.xml": `<?xml version="1.0"?><workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` +
			`<workbookPr date1904="1"/><sheets><sheet name="Mac" sheetId="1" r:id="rId1"/></sheets></workbook>`,
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/styles.xml":              `<styleSheet><cellXfs><xf numFmtId="14"/></cellXfs></styleSheet>`,
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="A1" s="0"><v>0</v></c></row>`),
	})

	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{{"1904-01-01"}})
}

func TestConvertToQsheetEscapesCellText(t *testing.T) {
	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Quotes"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/sharedStrings.xml":       `<sst><si><t>say "hi" \ &amp; bye</t></si></sst>`,
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="A1" t="s"><v>0</v></c></row>`),
	})

	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{{`say "hi" \ & bye`}})
}

func TestConvertToQsheetWideColumnReferences(t *testing.T) {
	// AA is column 27: a reference past Z is base-26, not a single letter.
	doc := convert(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Wide"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="AA1"><v>27</v></c></row>`),
	})

	rows := doc.Tabs[0].Data.Rows
	if len(rows) != 1 || len(rows[0]) != 27 {
		t.Fatalf("got %d rows of width %d, want 1 row of width 27", len(rows), len(rows[0]))
	}
	if rows[0][26] != "27" {
		t.Errorf("column AA = %q, want %q", rows[0][26], "27")
	}
}

func TestConvertToQsheetSkipsNonWorksheetRelationships(t *testing.T) {
	// A chartsheet has no rows to convert; the workbook's other sheets still do.
	doc := convert(t, map[string]string{
		"_rels/.rels":     rootRels,
		"xl/workbook.xml": workbookXML("Chart", "Data"),
		"xl/_rels/workbook.xml.rels": `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chartsheet" Target="chartsheets/sheet1.xml"/>` +
			`<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>` +
			`</Relationships>`,
		"xl/chartsheets/sheet1.xml": `<?xml version="1.0"?><chartsheet/>`,
		"xl/worksheets/sheet2.xml":  sheetXML(`<row r="1"><c r="A1"><v>1</v></c></row>`),
	})

	if len(doc.Tabs) != 1 || doc.Tabs[0].Name != "Data" {
		t.Fatalf("got tabs %+v, want only Data", doc.Tabs)
	}
}

func TestConvertToQsheetFallsBackToDefaultWorkbookPart(t *testing.T) {
	// A package with no root relationships still converts: every writer puts
	// the workbook where the fallback looks for it.
	doc := convert(t, map[string]string{
		"xl/workbook.xml":            workbookXML("Sheet1"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="A1"><v>7</v></c></row>`),
	})

	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{{"7"}})
}

func TestConvertToQsheetRejectsNonSpreadsheets(t *testing.T) {
	tests := []struct {
		name  string
		parts map[string]string
		raw   []byte
	}{
		{name: "not a zip", raw: []byte("this is a plain text file, not a package")},
		{name: "zip without a workbook", parts: map[string]string{"hello.txt": "hi"}},
		{
			name: "workbook without sheets",
			parts: map[string]string{
				"_rels/.rels":     rootRels,
				"xl/workbook.xml": workbookXML(),
			},
		},
		{
			name: "sheet part missing",
			parts: map[string]string{
				"_rels/.rels":                rootRels,
				"xl/workbook.xml":            workbookXML("Gone"),
				"xl/_rels/workbook.xml.rels": workbookRels(1),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var (
				src  *bytes.Reader
				size int64
			)
			if tt.raw != nil {
				src, size = bytes.NewReader(tt.raw), int64(len(tt.raw))
			} else {
				src, size = buildXlsx(t, tt.parts)
			}
			_, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &bytes.Buffer{}})
			if !errors.Is(err, ErrNotSpreadsheet) {
				t.Fatalf("err = %v, want ErrNotSpreadsheet", err)
			}
		})
	}
}

func TestConvertToQsheetRejectsEmptyInput(t *testing.T) {
	_, err := ConvertToQsheet(ConvertToQsheetParams{Source: bytes.NewReader(nil), Size: 0, Out: &bytes.Buffer{}})
	if !errors.Is(err, ErrNotSpreadsheet) {
		t.Fatalf("err = %v, want ErrNotSpreadsheet", err)
	}
}

func TestConvertToQsheetRejectsOversizedWorkbooks(t *testing.T) {
	names := make([]string, MaxSheets+1)
	for i := range names {
		names[i] = fmt.Sprintf("S%d", i)
	}
	parts := map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML(names...),
		"xl/_rels/workbook.xml.rels": workbookRels(len(names)),
	}
	for i := 1; i <= len(names); i++ {
		parts[fmt.Sprintf("xl/worksheets/sheet%d.xml", i)] = sheetXML(`<row r="1"><c r="A1"><v>1</v></c></row>`)
	}

	src, size := buildXlsx(t, parts)
	_, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &bytes.Buffer{}})
	if !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
}

func TestConvertToQsheetRejectsOverlongSheets(t *testing.T) {
	var rows strings.Builder
	fmt.Fprintf(&rows, `<row r="%d"><c r="A%d"><v>1</v></c></row>`, MaxRows+1, MaxRows+1)

	src, size := buildXlsx(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Long"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/worksheets/sheet1.xml":   sheetXML(rows.String()),
	})
	_, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &bytes.Buffer{}})
	if !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
}

func TestConvertToQsheetRejectsAnOverExpandingPart(t *testing.T) {
	// A zip stores a part compressed, so a small archive can carry a huge one.
	// The shared-string table is the sharpest version of that: highly
	// repetitive XML compresses to almost nothing, and every entry it declares
	// costs a slot in memory. The bound has to be on what is read, not on what
	// the archive or the entry header claims.
	var sst strings.Builder
	sst.WriteString("<sst>")
	for sst.Len() <= MaxSharedStringBytes {
		sst.WriteString("<si><t>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</t></si>")
	}
	sst.WriteString("</sst>")

	src, size := buildXlsx(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Big"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/sharedStrings.xml":       sst.String(),
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="A1" t="s"><v>0</v></c></row>`),
	})
	if size > 4<<20 {
		t.Fatalf("the compressed archive is %d bytes; the point is that it is small", size)
	}

	_, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &bytes.Buffer{}})
	if !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
}

func TestConvertToQsheetReportsWhatItWrote(t *testing.T) {
	src, size := buildXlsx(t, map[string]string{
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("A", "B"),
		"xl/_rels/workbook.xml.rels": workbookRels(2),
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="A1"><v>1</v></c><c r="B1"><v>2</v></c></row>`),
		"xl/worksheets/sheet2.xml":   sheetXML(`<row r="1"><c r="A1"><v>3</v></c></row>`),
	})

	result, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &bytes.Buffer{}})
	if err != nil {
		t.Fatalf("ConvertToQsheet: %v", err)
	}
	want := ConvertToQsheetResult{Tabs: 2, Rows: 2, Cells: 3}
	if result != want {
		t.Errorf("result = %+v, want %+v", result, want)
	}
}

func TestConvertToQsheetRejectsASheetTargetThatClimbsOut(t *testing.T) {
	// The worksheet is in the package. The relationship reaches it by climbing
	// out and back in; that target is not a part, so the workbook has nothing
	// to convert.
	src, size := buildXlsx(t, map[string]string{
		"_rels/.rels":     rootRels,
		"xl/workbook.xml": workbookXML("Hidden"),
		"xl/_rels/workbook.xml.rels": `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="../../xl/worksheets/sheet1.xml"/>` +
			`</Relationships>`,
		"xl/worksheets/sheet1.xml": sheetXML(`<row r="1"><c r="A1"><v>1</v></c></row>`),
	})
	_, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &bytes.Buffer{}})
	if !errors.Is(err, ErrNotSpreadsheet) {
		t.Fatalf("err = %v, want ErrNotSpreadsheet", err)
	}
}

func TestConvertToQsheetReadsASheetTargetThatStaysInside(t *testing.T) {
	doc := convert(t, map[string]string{
		"_rels/.rels":     rootRels,
		"xl/workbook.xml": workbookXML("Kept"),
		"xl/_rels/workbook.xml.rels": `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/../worksheets/sheet1.xml"/>` +
			`</Relationships>`,
		"xl/worksheets/sheet1.xml": sheetXML(`<row r="1"><c r="A1"><v>1</v></c></row>`),
	})
	assertRows(t, doc.Tabs[0].Data.Rows, [][]string{{"1"}})
}

func TestConvertToQsheetRejectsAnEntryThatClimbsOut(t *testing.T) {
	src, size := buildXlsx(t, map[string]string{
		"../evil.xml":                "nope",
		"_rels/.rels":                rootRels,
		"xl/workbook.xml":            workbookXML("Sheet1"),
		"xl/_rels/workbook.xml.rels": workbookRels(1),
		"xl/worksheets/sheet1.xml":   sheetXML(`<row r="1"><c r="A1"><v>1</v></c></row>`),
	})
	_, err := ConvertToQsheet(ConvertToQsheetParams{Source: src, Size: size, Out: &bytes.Buffer{}})
	if !errors.Is(err, ErrNotSpreadsheet) {
		t.Fatalf("err = %v, want ErrNotSpreadsheet", err)
	}
}

// assertRows compares a tab's rows against what the workbook should have
// produced, reporting the whole grid rather than the first cell that differs.
func assertRows(t *testing.T, got, want [][]string) {
	t.Helper()
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("rows =\n  %v\nwant\n  %v", got, want)
	}
}
