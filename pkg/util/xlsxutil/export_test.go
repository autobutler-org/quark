package xlsxutil

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"testing"
)

// export runs ExportQsheet over a .qsheet document and returns the workbook.
func export(t *testing.T, doc string) ([]byte, ExportQsheetResult) {
	t.Helper()
	var out bytes.Buffer
	result, err := ExportQsheet(ExportQsheetParams{Source: strings.NewReader(doc), Out: &out})
	if err != nil {
		t.Fatalf("ExportQsheet: %v", err)
	}
	return out.Bytes(), result
}

// readPart returns one part of a workbook as text.
func readPart(t *testing.T, book []byte, name string) string {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(book), int64(len(book)))
	if err != nil {
		t.Fatalf("open workbook: %v", err)
	}
	f, err := zr.Open(name)
	if err != nil {
		t.Fatalf("open %s: %v", name, err)
	}
	defer f.Close()
	body, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return string(body)
}

// roundTrip exports doc and reads the workbook back with the importer, so the
// test checks the workbook a real reader sees rather than the XML text.
func roundTrip(t *testing.T, doc string) qsheetDoc {
	t.Helper()
	book, _ := export(t, doc)
	var out bytes.Buffer
	if _, err := ConvertToQsheet(ConvertToQsheetParams{
		Source: bytes.NewReader(book),
		Size:   int64(len(book)),
		Out:    &out,
	}); err != nil {
		t.Fatalf("re-import: %v", err)
	}
	var got qsheetDoc
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("decode re-import: %v", err)
	}
	return got
}

func TestExportQsheetRoundTripsEveryTab(t *testing.T) {
	doc := `{"tabs":[
		{"name":"Budget","data":{"rows":[["Item","Cost"],["Rent","1200"],["Food","350.5"]]}},
		{"name":"Notes","data":{"rows":[["a <b> & \"c\""],["","x"]]},"columnWidths":[120,80]}
	]}`
	got := roundTrip(t, doc)
	if len(got.Tabs) != 2 || got.Tabs[0].Name != "Budget" || got.Tabs[1].Name != "Notes" {
		t.Fatalf("tabs = %+v", got.Tabs)
	}
	assertRows(t, got.Tabs[0].Data.Rows, [][]string{{"Item", "Cost"}, {"Rent", "1200"}, {"Food", "350.5"}})
	assertRows(t, got.Tabs[1].Data.Rows, [][]string{{"a <b> & \"c\"", ""}, {"", "x"}})
}

func TestExportQsheetWritesNumbersAsNumbersAndFormulasAsText(t *testing.T) {
	book, result := export(t, `{"tabs":[{"name":"S","data":{"rows":[
		["42","-3.5","1e3","007","1234567890123456","=SUM(A1:B1)","0x1F","Inf","TRUE"]
	]}}]}`)
	sheet := readPart(t, book, "xl/worksheets/sheet1.xml")
	for _, want := range []string{
		`<c r="A1"><v>42</v></c>`,
		`<c r="B1"><v>-3.5</v></c>`,
		`<c r="C1"><v>1e3</v></c>`,
	} {
		if !strings.Contains(sheet, want) {
			t.Errorf("sheet lacks %s:\n%s", want, sheet)
		}
	}
	// A leading zero, more digits than Excel keeps, a formula, and what
	// ParseFloat accepts beyond plain decimals all stay text.
	for _, ref := range []string{"D1", "E1", "F1", "G1", "H1", "I1"} {
		if !strings.Contains(sheet, `<c r="`+ref+`" t="inlineStr">`) {
			t.Errorf("%s is not text:\n%s", ref, sheet)
		}
	}
	if !strings.Contains(sheet, `<t xml:space="preserve">=SUM(A1:B1)</t>`) {
		t.Errorf("formula text missing:\n%s", sheet)
	}
	if result.Tabs != 1 || result.Rows != 1 || result.Cells != 9 {
		t.Errorf("result = %+v", result)
	}
}

func TestExportQsheetCarriesFormats(t *testing.T) {
	book, _ := export(t, `{"tabs":[{"name":"S","data":{"rows":[["1","2","3","45000"],["",""]]},
		"frozenRows":1,"frozenColumns":1,
		"formats":[
			{"row":0,"col":0,"bold":true,"italic":true,"textColor":4294901760},
			{"row":0,"col":1,"fillColor":4278255360,"align":"center","numberFormat":"currency","decimals":0},
			{"row":0,"col":2,"numberFormat":"percent","decimals":1},
			{"row":0,"col":3,"numberFormat":"date"},
			{"row":1,"col":1,"fillColor":4278255360,"align":"center","numberFormat":"currency","decimals":0},
			{"row":9,"col":9,"bold":true}
		]}]}`)
	styles := readPart(t, book, "xl/styles.xml")
	for _, want := range []string{
		`<font><b/><i/><sz val="11"/><color rgb="FFFF0000"/>`,
		`<fgColor rgb="FF00FF00"/>`,
		`formatCode="&#34;$&#34;#,##0"`,
		`formatCode="#,##0.0%"`,
		`formatCode="yyyy-mm-dd"`,
		`<alignment horizontal="center"/>`,
		// The plain default plus four distinct styles; the repeat and the
		// format outside the sheet add none.
		`<cellXfs count="5">`,
	} {
		if !strings.Contains(styles, want) {
			t.Errorf("styles lack %s:\n%s", want, styles)
		}
	}
	sheet := readPart(t, book, "xl/worksheets/sheet1.xml")
	for _, want := range []string{
		`<pane xSplit="1" ySplit="1" topLeftCell="B2" activePane="bottomRight" state="frozen"/>`,
		`<c r="A1" s="1">`,
		// An empty cell with a fill is still written, so the fill shows.
		`<c r="B2" s="2"/>`,
	} {
		if !strings.Contains(sheet, want) {
			t.Errorf("sheet lacks %s:\n%s", want, sheet)
		}
	}

	// The date format reads back as a date, which is what tells a real
	// reader it is one.
	got := roundTrip(t, `{"tabs":[{"name":"S","data":{"rows":[["45000"]]},"formats":[{"row":0,"col":0,"numberFormat":"date"}]}]}`)
	assertRows(t, got.Tabs[0].Data.Rows, [][]string{{"2023-03-15"}})
}

func TestExportQsheetMakesSheetNamesExcelAccepts(t *testing.T) {
	book, _ := export(t, `{"tabs":[
		{"name":"a/b:c","data":{"rows":[["x"]]}},
		{"name":"A_B_C","data":{"rows":[["x"]]}},
		{"name":"","data":{"rows":[["x"]]}},
		{"name":"This name is far longer than thirty-one characters","data":{"rows":[["x"]]}}
	]}`)
	workbook := readPart(t, book, "xl/workbook.xml")
	for _, want := range []string{
		`name="a_b_c"`,
		`name="A_B_C (2)"`,
		`name="Sheet3"`,
		`name="This name is far longer than th"`,
	} {
		if !strings.Contains(workbook, want) {
			t.Errorf("workbook lacks %s:\n%s", want, workbook)
		}
	}
}

func TestExportQsheetWithNoTabsWritesOneBlankSheet(t *testing.T) {
	got := roundTrip(t, `{"tabs":[]}`)
	if len(got.Tabs) != 1 || got.Tabs[0].Name != "Sheet1" {
		t.Fatalf("tabs = %+v", got.Tabs)
	}
}

func TestExportQsheetSkipsUnknownKeys(t *testing.T) {
	got := roundTrip(t, `{"version":2,"meta":{"a":[1,2]},"tabs":[{"name":"S","data":{"rows":[["1"]]},"filters":[{"column":0}]}]}`)
	assertRows(t, got.Tabs[0].Data.Rows, [][]string{{"1"}})
}

func TestExportQsheetRejectsOtherDocuments(t *testing.T) {
	for name, doc := range map[string]string{
		"not json":  "PK\x03\x04",
		"array":     `[1,2]`,
		"truncated": `{"tabs":[{"name":"S","data":{"rows":[["1"`,
		"bad rows":  `{"tabs":[{"name":"S","data":{"rows":"nope"}}]}`,
	} {
		t.Run(name, func(t *testing.T) {
			_, err := ExportQsheet(ExportQsheetParams{Source: strings.NewReader(doc), Out: io.Discard})
			if !errors.Is(err, ErrNotQsheet) {
				t.Fatalf("err = %v, want ErrNotQsheet", err)
			}
		})
	}
}

func TestExportQsheetRejectsOverlongSheets(t *testing.T) {
	var b strings.Builder
	b.WriteString(`{"tabs":[{"name":"S","data":{"rows":[`)
	for i := 0; i <= MaxRows; i++ {
		if i > 0 {
			b.WriteByte(',')
		}
		b.WriteString(`[]`)
	}
	b.WriteString(`]}}]}`)
	_, err := ExportQsheet(ExportQsheetParams{Source: strings.NewReader(b.String()), Out: io.Discard})
	if !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
}

func TestCappedReaderReportsTooLarge(t *testing.T) {
	exact := &cappedReader{r: strings.NewReader("abcd"), remaining: 4}
	if body, err := io.ReadAll(exact); err != nil || string(body) != "abcd" {
		t.Fatalf("exact fit: %q, %v", body, err)
	}
	over := &cappedReader{r: strings.NewReader("abcde"), remaining: 4}
	if _, err := io.ReadAll(over); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
}

func TestColumnName(t *testing.T) {
	for col, want := range map[int]string{0: "A", 25: "Z", 26: "AA", 701: "ZZ", 702: "AAA", 16383: "XFD"} {
		if got := columnName(col); got != want {
			t.Errorf("columnName(%d) = %q, want %q", col, got, want)
		}
	}
}
