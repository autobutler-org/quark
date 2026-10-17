package xlsutil_test

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/xlsutil"
)

// FuzzConvertToQsheet feeds mutated workbooks through ConvertToQsheet. The
// seeds run as ordinary tests under `go test`; `go test -fuzz=FuzzConvertToQsheet
// ./pkg/util/xlsutil` explores from them. Only the container library runs
// under recover(), so a panic in this package's own record reader fails the
// run. Whatever the input, the result is a classified error or a well-formed
// envelope whose rows are all one width.
func FuzzConvertToQsheet(f *testing.F) {
	saved, err := os.ReadFile("testdata/libreoffice.xls")
	if err != nil {
		f.Fatal(err)
	}
	f.Add(saved)
	for _, seed := range fuzzSeeds() {
		f.Add(seed)
	}

	f.Fuzz(func(t *testing.T, file []byte) {
		var out bytes.Buffer
		res, err := xlsutil.ConvertToQsheet(xlsutil.ConvertToQsheetParams{
			Source: bytes.NewReader(file),
			Size:   int64(len(file)),
			Out:    &out,
		})
		if err != nil {
			if !errors.Is(err, xlsutil.ErrNotSpreadsheet) && !errors.Is(err, xlsutil.ErrTooLarge) && !errors.Is(err, xlsutil.ErrEncrypted) {
				t.Fatalf("unclassified error: %v", err)
			}
			return
		}

		var doc qsheet
		if err := json.Unmarshal(out.Bytes(), &doc); err != nil {
			t.Fatalf("output is not JSON: %v", err)
		}
		if len(doc.Tabs) != res.Tabs {
			t.Fatalf("%d tabs written, %d reported", len(doc.Tabs), res.Tabs)
		}
		total := 0
		for _, tab := range doc.Tabs {
			if len(tab.Data.Rows) == 0 {
				t.Fatalf("tab %q has no rows", tab.Name)
			}
			for _, row := range tab.Data.Rows {
				if len(row) != len(tab.Data.Rows[0]) {
					t.Fatalf("tab %q has ragged rows", tab.Name)
				}
			}
			total += len(tab.Data.Rows)
		}
		if total != res.Rows {
			t.Fatalf("%d rows written, %d reported", total, res.Rows)
		}
	})
}

// fuzzSeeds are built workbooks that between them reach every record the
// reader acts on.
func fuzzSeeds() [][]byte {
	everything := book{
		pre: [][]byte{
			rec(tDateMode, uint16(1)),
			rec(tFormat, uint16(164), compressed("yyyy-mm-dd")),
			xf(0), xf(164),
		},
		sheets: []sheetSrc{
			{name: "Cells", cells: [][]byte{
				number(0, 0, 1, 1000),
				rec(tRK, uint16(0), uint16(1), uint16(0), uint32(7<<2|2)),
				rec(tMulRK, uint16(1), uint16(0), uint16(0), uint32(1<<2|2), uint16(0), uint32(2<<2|2), uint16(1)),
				labelSST(2, 0, 0),
				rec(tLabel, uint16(2), uint16(1), uint16(0), wide("ü")),
				rec(tBoolErr, uint16(3), uint16(0), uint16(0), byte(1), byte(0)),
				formula(3, 1, special(0, 0)),
				rec(tString, compressed("result")),
				formula(3, 2, numberResult(2.5)),
			}},
			{name: "Chart", dt: 2, raw: append(bof(0x0020), eof()...)},
			{name: "Empty"},
		},
		post: [][]byte{
			rec(tSST, uint32(2), uint32(2), []byte{3, 0, 0}, "ab"),
			rec(tContinue, byte(1), uint16('c'), compressed("d")),
		},
	}
	return [][]byte{
		xls(everything.stream()),
		oneSheet([]string{"a"}, labelSST(0, 0, 0)),
		xls(book{pre: [][]byte{rec(tFilePass, make([]byte, 54))}}.stream()),
	}
}
