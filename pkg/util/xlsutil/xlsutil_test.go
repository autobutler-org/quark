package xlsutil_test

// cspell:ignore abcdéfgh DATEMODE éfgh Fmla résumé

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"os"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/xlsutil"
	"github.com/autobutler-org/quark/pkg/util/xlsxutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// qsheet is the envelope as the editor reads it.
type qsheet struct {
	Tabs []struct {
		Name string `json:"name"`
		Data struct {
			Rows [][]string `json:"rows"`
		} `json:"data"`
	} `json:"tabs"`
}

func convert(t *testing.T, file []byte) (qsheet, xlsutil.ConvertToQsheetResult, error) {
	t.Helper()
	var out bytes.Buffer
	res, err := xlsutil.ConvertToQsheet(xlsutil.ConvertToQsheetParams{
		Source: bytes.NewReader(file),
		Size:   int64(len(file)),
		Out:    &out,
	})
	var doc qsheet
	if err == nil {
		require.NoError(t, json.Unmarshal(out.Bytes(), &doc), "output is not JSON: %s", out.String())
	}
	return doc, res, err
}

func rows(t *testing.T, file []byte) [][]string {
	t.Helper()
	doc, _, err := convert(t, file)
	require.NoError(t, err)
	require.Len(t, doc.Tabs, 1)
	return doc.Tabs[0].Data.Rows
}

func TestConvertLibreOfficeFile(t *testing.T) {
	// testdata/libreoffice.xls was saved by LibreOffice Calc as "Excel 97"
	// from a three-sheet document. Its Workbook stream is small enough to
	// live in the compound file's mini stream.
	file, err := os.ReadFile("testdata/libreoffice.xls")
	require.NoError(t, err)

	doc, res, err := convert(t, file)
	require.NoError(t, err)
	require.Len(t, doc.Tabs, 3)

	assert.Equal(t, "Budget", doc.Tabs[0].Name)
	assert.Equal(t, [][]string{
		{"Item", "Cost", "Due"},
		{"Café ☕", "3.5", "2024-03-15"},
		{"Total", "103.5", ""},
	}, doc.Tabs[0].Data.Rows)

	assert.Equal(t, "Empty", doc.Tabs[1].Name)
	assert.Equal(t, [][]string{{""}}, doc.Tabs[1].Data.Rows)

	assert.Equal(t, "Sparse", doc.Tabs[2].Name)
	assert.Equal(t, [][]string{
		{"", "", "", ""},
		{"", "", "", ""},
		{"", "", "", "42"},
	}, doc.Tabs[2].Data.Rows)

	assert.Equal(t, xlsutil.ConvertToQsheetResult{Tabs: 3, Rows: 7, Cells: 9}, res)
}

func TestConvertCellRecords(t *testing.T) {
	// RK packs a 30-bit integer or the top of a double, optionally /100.
	rkInt := func(n int32) uint32 { return uint32(n)<<2 | 0x02 }
	rkFloat := func(v float64) uint32 { return uint32(math.Float64bits(v) >> 32) }

	got := rows(t, oneSheet([]string{"shared"},
		number(0, 0, 0, 1.25),
		rec(tRK, uint16(0), uint16(1), uint16(0), rkInt(-7)),
		rec(tRK, uint16(0), uint16(2), uint16(0), rkInt(1234)|0x01),
		rec(tRK, uint16(0), uint16(3), uint16(0), rkFloat(2.5)),
		rec(tMulRK, uint16(1), uint16(0), uint16(0), rkInt(1), uint16(0), rkInt(2), uint16(0), rkInt(3), uint16(2)),
		labelSST(2, 0, 0),
		rec(tLabel, uint16(2), uint16(1), uint16(0), wide("wide ✓")),
		rec(tLabel, uint16(2), uint16(2), uint16(0), compressed("narrow")),
		rec(tBoolErr, uint16(3), uint16(0), uint16(0), byte(1), byte(0)),
		rec(tBoolErr, uint16(3), uint16(1), uint16(0), byte(0), byte(0)),
		rec(tBoolErr, uint16(3), uint16(2), uint16(0), byte(0x07), byte(1)),
		rec(tBoolErr, uint16(3), uint16(3), uint16(0), byte(0x2A), byte(1)),
	))
	assert.Equal(t, [][]string{
		{"1.25", "-7", "12.34", "2.5"},
		{"1", "2", "3", ""},
		{"shared", "wide ✓", "narrow", ""},
		{"TRUE", "FALSE", "#DIV/0!", "#N/A"},
	}, got)
}

func TestConvertFormulaResults(t *testing.T) {
	got := rows(t, oneSheet(nil,
		formula(0, 0, numberResult(42)),
		formula(0, 1, special(1, 1)),
		formula(0, 2, special(2, 0x17)),
		// An empty-string result displays nothing.
		formula(0, 3, special(3, 0)),
		// A string result is carried by the STRING record that follows,
		// even with a shared formula between them.
		formula(1, 0, special(0, 0)),
		rec(tShrFmla, make([]byte, 10)),
		rec(tString, wide("résumé")),
		// A STRING with no formula waiting for it belongs to nothing.
		rec(tString, compressed("stray")),
		// A string formula whose STRING never comes leaves its cell empty.
		formula(1, 1, special(0, 0)),
		number(1, 2, 0, 9),
		rec(tString, compressed("late")),
	))
	assert.Equal(t, [][]string{
		{"42", "TRUE", "#REF!"},
		{"résumé", "", "9"},
	}, got)
}

func TestConvertDates(t *testing.T) {
	cells := [][]byte{
		number(0, 0, 0, 45366),      // XF 0: General, a number
		number(0, 1, 1, 45366),      // XF 1: builtin 14, a date
		number(0, 2, 2, 45366.75),   // XF 2: custom yyyy-mm-dd hh:mm
		number(0, 3, 3, 0.5),        // XF 3: builtin 21, a time
		number(0, 4, 4, 45366),      // XF 4: a currency whose locale tag holds a "d"
		number(0, 5, 1, 1e12),       // a date format on a number past year 9999
		number(0, 6, 99, 45366),     // an XF index past the table
		number(1, 0, 1, math.NaN()), // a date format on NaN
	}
	globals := [][]byte{
		rec(tFormat, uint16(164), compressed("yyyy-mm-dd hh:mm")),
		rec(tFormat, uint16(165), compressed(`[$$-409]#,##0.00`)),
		xf(0), xf(14), xf(164), xf(21), xf(165),
	}

	file := xls(book{pre: globals, sheets: []sheetSrc{{name: "S", cells: cells}}}.stream())
	assert.Equal(t, [][]string{
		{"45366", "2024-03-15", "2024-03-15 18:00:00", "12:00:00", "45366", "1000000000000", "45366"},
		{"NaN", "", "", "", "", "", ""},
	}, rows(t, file))

	// DATEMODE 1 counts from 1904.
	file1904 := xls(book{
		pre:    append([][]byte{rec(tDateMode, uint16(1))}, globals...),
		sheets: []sheetSrc{{name: "S", cells: [][]byte{number(0, 0, 1, 0)}}},
	}.stream())
	assert.Equal(t, [][]string{{"1904-01-01"}}, rows(t, file1904))
}

func TestConvertSkipsWhatIsNotACell(t *testing.T) {
	chart := append(bof(0x0020), number(0, 0, 0, 666)...)
	chart = append(chart, eof()...)

	file := xls(book{
		sheets: []sheetSrc{
			{name: "Data", cells: [][]byte{
				rec(tDimensions, make([]byte, 14)),
				number(0, 0, 0, 1),
				// An embedded chart is a nested substream; its records are
				// not this sheet's cells.
				chart,
				number(1, 1, 0, 2),
				// Cells arrive in row order; one for a row already written
				// is dropped rather than misplaced.
				number(0, 2, 0, 3),
				// A cell record too short to hold its value is skipped.
				rec(tNumber, uint16(1), uint16(0), uint16(0), uint16(0)),
			}},
			// A chart sheet is not a worksheet, and is not a tab.
			{name: "Chart1", dt: 2, raw: append(bof(0x0020), eof()...)},
		},
		post: [][]byte{sst()},
	}.stream())

	doc, res, err := convert(t, file)
	require.NoError(t, err)
	require.Len(t, doc.Tabs, 1)
	assert.Equal(t, "Data", doc.Tabs[0].Name)
	assert.Equal(t, [][]string{{"1", "", ""}, {"", "2", ""}}, doc.Tabs[0].Data.Rows)
	assert.Equal(t, xlsutil.ConvertToQsheetResult{Tabs: 1, Rows: 2, Cells: 2}, res)
}

func TestConvertSharedStringsAcrossContinue(t *testing.T) {
	// String 0 starts compressed and runs into a CONTINUE whose option byte
	// switches the rest to two bytes a character. String 1 has formatting
	// runs and phonetic data, both split across the next boundary, and its
	// header starts in one record and ends in the next.
	first := []any{uint32(3), uint32(3)}
	first = append(first, []byte{10, 0, 0}, "abcd")
	cont1 := []any{byte(1)}
	for _, r := range "éfgh✓h" {
		cont1 = append(cont1, uint16(r))
	}
	// String 1: 2 chars, rich (0x08) and extended (0x04), 1 run, 6 ext bytes.
	cont1 = append(cont1, []byte{2, 0, 0x0C, 1})
	cont2 := []any{byte(0), uint32(6), "xy", uint32(0), byte(0)}
	// Four of the six phonetic bytes are left; then string 2.
	cont3 := []any{make([]byte, 5), compressed("z")}

	file := xls(book{
		sheets: []sheetSrc{{name: "S", cells: [][]byte{labelSST(0, 0, 0), labelSST(0, 1, 1), labelSST(0, 2, 2)}}},
		post: [][]byte{
			rec(tSST, first...),
			rec(tContinue, cont1...),
			rec(tContinue, cont2...),
			rec(tContinue, cont3...),
		},
	}.stream())
	assert.Equal(t, [][]string{{"abcdéfgh✓h", "xy", "z"}}, rows(t, file))
}

func TestConvertSharedStringCountIsNotTrusted(t *testing.T) {
	// The table claims four billion strings and holds two; nothing is sized
	// from the claim, and the two that are there are read.
	table := rec(tSST, uint32(math.MaxUint32), uint32(math.MaxUint32), compressed("a"), compressed("b"))
	file := xls(book{
		sheets: []sheetSrc{{name: "S", cells: [][]byte{labelSST(0, 0, 1), labelSST(0, 1, 7)}}},
		post:   [][]byte{table},
	}.stream())
	assert.Equal(t, [][]string{{"b"}}, rows(t, file))
}

func TestConvertRefusesEncrypted(t *testing.T) {
	filePass := xls(book{
		pre:    [][]byte{rec(tFilePass, uint16(1), make([]byte, 52))},
		sheets: []sheetSrc{{name: "S", cells: [][]byte{number(0, 0, 0, 1)}}},
	}.stream())
	_, _, err := convert(t, filePass)
	assert.ErrorIs(t, err, xlsutil.ErrEncrypted)

	// A password-protected .xlsx is a compound file too, often renamed .xls.
	encryptedPackage := buildCFB(
		cfbStream{name: "EncryptionInfo", data: []byte{4, 0, 4, 0}},
		cfbStream{name: "EncryptedPackage", data: []byte{1, 2, 3}},
	)
	_, _, err = convert(t, encryptedPackage)
	assert.ErrorIs(t, err, xlsutil.ErrEncrypted)
}

func TestConvertRejectsWhatIsNotBIFF8(t *testing.T) {
	sheet := []sheetSrc{{name: "S", cells: [][]byte{number(0, 0, 0, 1)}}}
	good := book{sheets: sheet, post: [][]byte{sst()}}.stream()
	biff5BOF := append([]byte(nil), good...)
	biff5BOF[4], biff5BOF[5] = 0x00, 0x05
	beyond := uint32(1 << 20)

	cases := map[string][]byte{
		"plain text":       []byte("Item,Cost\nCafé,3.5\n"),
		"a zip":            []byte("PK\x03\x04 an xlsx, really"),
		"a lone signature": {0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1},
		"no Workbook":      buildCFB(cfbStream{name: "WordDocument", data: []byte("hi")}),
		"Excel 95":         buildCFB(cfbStream{name: "Book", data: good}),
		"a BIFF5 BOF":      xls(biff5BOF),
		"no BOF":           xls(append(number(0, 0, 0, 1), good...)),
		"empty stream":     buildCFB(cfbStream{name: "Workbook", sizeOverride: true}),
		"oversized record": xls(append(bof(0x0005), rawRec(0x0001, 9000, make([]byte, 9000))...)),
		"no globals EOF":   xls(append(bof(0x0005), sst("a")...)),
		"sheet off the end": xls(book{
			sheets: []sheetSrc{{name: "S", offset: &beyond}},
		}.stream()),
		"sheet is not a worksheet BOF": xls(book{
			sheets: []sheetSrc{{name: "S", raw: append(bof(0x0020), eof()...)}},
		}.stream()),
		"a string split mid-character": xls(book{
			sheets: []sheetSrc{{name: "S"}},
			post: [][]byte{
				rec(tSST, uint32(1), uint32(1), []byte{2, 0, 1, 'a'}),
				rec(tContinue, byte(1), []byte{0, 'b'}),
			},
		}.stream()),
		"a string past its record": xls(book{
			sheets: []sheetSrc{{name: "S"}},
			post:   [][]byte{rec(tSST, uint32(1), uint32(1), []byte{9, 0, 0, 'a'})},
		}.stream()),
	}
	// A truncated record needs the stream to really end, past the mini
	// stream's cutoff: the padding the builder adds would otherwise read as
	// more records.
	truncated := append(bof(0x0005), rec(0x0001, make([]byte, miniCutoff))...)
	truncated = append(truncated, rawRec(0x0001, 100, make([]byte, 10))...)
	cases["truncated record"] = buildCFB(cfbStream{
		name: "Workbook", data: truncated, sizeOverride: true, declaredSize: uint32(len(truncated)),
	})

	for name, file := range cases {
		t.Run(name, func(t *testing.T) {
			_, _, err := convert(t, file)
			assert.ErrorIs(t, err, xlsutil.ErrNotSpreadsheet)
		})
	}

	t.Run("empty file", func(t *testing.T) {
		_, err := xlsutil.ConvertToQsheet(xlsutil.ConvertToQsheetParams{
			Source: bytes.NewReader(nil), Out: &bytes.Buffer{},
		})
		assert.ErrorIs(t, err, xlsutil.ErrNotSpreadsheet)
	})
}

func TestConvertEnforcesLimits(t *testing.T) {
	tooMany := make([]sheetSrc, xlsxutil.MaxSheets+1)
	for i := range tooMany {
		tooMany[i] = sheetSrc{name: "S"}
	}
	far := func(row, col uint16) []sheetSrc {
		return []sheetSrc{{name: "S", cells: [][]byte{number(row, col, 0, 1)}}}
	}

	cases := map[string]book{
		"too many sheets": {sheets: tooMany},
		"too wide":        {sheets: far(0, xlsxutil.MaxColumns)},
		"too many cells":  {sheets: far(999, 1000)},
		"too many rows across sheets": {sheets: append(far(65_535, 0),
			sheetSrc{name: "T", cells: [][]byte{number(65_535, 0, 0, 1)}})},
	}
	for name, b := range cases {
		t.Run(name, func(t *testing.T) {
			var out bytes.Buffer
			file := xls(b.stream())
			_, err := xlsutil.ConvertToQsheet(xlsutil.ConvertToQsheetParams{
				Source: bytes.NewReader(file), Size: int64(len(file)), Out: &out,
			})
			assert.ErrorIs(t, err, xlsutil.ErrTooLarge)
			// Every sheet is measured before anything is written.
			assert.Zero(t, out.Len())
		})
	}

	t.Run("at the column limit", func(t *testing.T) {
		got := rows(t, xls(book{sheets: far(0, xlsxutil.MaxColumns-1)}.stream()))
		require.Len(t, got, 1)
		assert.Len(t, got[0], xlsxutil.MaxColumns)
	})
}

func TestConvertHostileContainer(t *testing.T) {
	t.Run("a Workbook stream whose sector chain loops", func(t *testing.T) {
		// The stream's last sector chains back to its first. Claiming more
		// than the file holds is refused before a byte is read; claiming
		// less, the loop is read round only until the claim runs out, and
		// the globals never reach their EOF.
		globals := append(bof(0x0005), rec(0x0001, make([]byte, 100))...)
		huge := buildCFB(cfbStream{name: "Workbook", data: globals, loop: true, sizeOverride: true, declaredSize: 16 << 20})
		within := buildCFB(cfbStream{name: "Workbook", data: globals, loop: true, sizeOverride: true, declaredSize: 5000})
		for _, file := range [][]byte{huge, within} {
			_, _, err := convert(t, file)
			assert.ErrorIs(t, err, xlsutil.ErrNotSpreadsheet)
		}
	})

	t.Run("every sheet pointing at the same large substream", func(t *testing.T) {
		// A real workbook reads each sheet's records twice. Sixty-four tabs
		// all naming one substream that is most of the file would read it
		// 128 times; the read budget stops that.
		filler := rec(0x0001, make([]byte, 8000))
		cells := [][]byte{number(0, 0, 0, 1)}
		for range 40 {
			cells = append(cells, filler)
		}
		shared := uint32(0)
		sheets := []sheetSrc{{name: "S0", cells: cells}}
		for i := 1; i < xlsxutil.MaxSheets; i++ {
			sheets = append(sheets, sheetSrc{name: "S", raw: []byte{}, offset: &shared})
		}
		// Every other BOUNDSHEET points at the first sheet's BOF, which is
		// where the builder put it.
		b := book{sheets: sheets}
		first := bytes.Index(b.stream(), bof(0x0010))
		require.Positive(t, first)
		shared = uint32(first)
		stream := b.stream()
		require.Equal(t, first, bytes.Index(stream, bof(0x0010)))

		_, _, err := convert(t, xls(stream))
		assert.ErrorIs(t, err, xlsutil.ErrNotSpreadsheet)
	})
}

// failingReaderAt fails every read past the first n bytes, like a disk that
// dies partway through the file.
type failingReaderAt struct {
	data []byte
	n    int64
}

func (f failingReaderAt) ReadAt(p []byte, off int64) (int, error) {
	if off+int64(len(p)) > f.n {
		return 0, errors.New("disk on fire")
	}
	return bytes.NewReader(f.data).ReadAt(p, off)
}

func TestConvertReportsSourceFailures(t *testing.T) {
	// A failing disk is the server's problem, not the file's: the error says
	// so and is not one of the 400 sentinels.
	file := oneSheet([]string{"a"}, labelSST(0, 0, 0))
	_, err := xlsutil.ConvertToQsheet(xlsutil.ConvertToQsheetParams{
		Source: failingReaderAt{data: file, n: 2048},
		Size:   int64(len(file)),
		Out:    &bytes.Buffer{},
	})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "disk on fire")
	assert.NotErrorIs(t, err, xlsutil.ErrNotSpreadsheet)
	assert.NotErrorIs(t, err, xlsutil.ErrTooLarge)
}

func TestConvertRequiresSourceAndOut(t *testing.T) {
	_, err := xlsutil.ConvertToQsheet(xlsutil.ConvertToQsheetParams{Size: 1, Out: &bytes.Buffer{}})
	require.Error(t, err)
	_, err = xlsutil.ConvertToQsheet(xlsutil.ConvertToQsheetParams{Source: strings.NewReader("x"), Size: 1})
	require.Error(t, err)
}
