package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
)

// seedOds writes a one-sheet OpenDocument spreadsheet at name under root,
// holding the same Ledger the .xlsx fixture does.
func seedOds(t *testing.T, root, name string) {
	t.Helper()
	const mime = "application/vnd.oasis.opendocument.spreadsheet"
	cell := func(text string) string {
		return `<table:table-cell office:value-type="string"><text:p>` + text + `</text:p></table:table-cell>`
	}
	parts := []struct{ name, body string }{
		{"mimetype", mime},
		{"META-INF/manifest.xml", `<?xml version="1.0" encoding="UTF-8"?>` +
			`<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">` +
			`<manifest:file-entry manifest:full-path="/" manifest:media-type="` + mime + `"/>` +
			`<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>` +
			`</manifest:manifest>`},
		{"content.xml", `<?xml version="1.0" encoding="UTF-8"?>` +
			`<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ` +
			`xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" ` +
			`xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">` +
			`<office:body><office:spreadsheet><table:table table:name="Ledger">` +
			`<table:table-row>` + cell("Item") + `</table:table-row>` +
			`<table:table-row>` + cell("Coffee") + `</table:table-row>` +
			`</table:table></office:spreadsheet></office:body></office:document-content>`},
	}
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, p := range parts {
		w, err := zw.Create(p.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, p.body); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	writeSeed(t, root, name, buf.Bytes())
}

// seedXls copies xlsutil's LibreOffice-saved Excel 97 workbook to name under
// root. Its first sheet is Budget, whose header row starts with Item.
func seedXls(t *testing.T, root, name string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "xlsutil", "testdata", "libreoffice.xls"))
	if err != nil {
		t.Fatal(err)
	}
	writeSeed(t, root, name, raw)
}

func writeSeed(t *testing.T, root, name string, content []byte) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, content, 0o600); err != nil {
		t.Fatal(err)
	}
}

func previewSheetParams(f xlsxFixture, filePath string, out io.Writer) fileutil.PreviewSheetParams {
	return fileutil.PreviewSheetParams{
		Ctx: context.Background(), Registry: f.params.Registry, FilePath: filePath, Out: out,
	}
}

func TestPreviewSheetStreamsEachFormatAndStoresNothing(t *testing.T) {
	for name, tc := range map[string]struct {
		workbook string
		seed     func(t *testing.T, root, name string)
		tab      string
		first    []string
	}{
		"xlsx": {"books/budget.xlsx", nil, "Ledger", []string{"Item"}},
		"ods":  {"books/budget.ods", seedOds, "Ledger", []string{"Item"}},
		"xls":  {"books/legacy.xls", seedXls, "Budget", []string{"Item", "Cost", "Due"}},
	} {
		t.Run(name, func(t *testing.T) {
			f := newXlsxFixture(t, "books/budget.xlsx")
			if tc.seed != nil {
				tc.seed(t, f.root, tc.workbook)
			}
			before, err := os.ReadDir(filepath.Join(f.root, "books"))
			if err != nil {
				t.Fatal(err)
			}

			var out bytes.Buffer
			result, err := fileutil.PreviewSheet(previewSheetParams(f, tc.workbook, &out))
			if err != nil {
				t.Fatalf("preview: %v", err)
			}
			var got fileutil.SheetPreview
			if err := json.Unmarshal(out.Bytes(), &got); err != nil {
				t.Fatalf("not one JSON object: %v\n%s", err, out.String())
			}
			if len(got.Tabs) != result.Tabs || got.Tabs[0].Name != tc.tab {
				t.Fatalf("tabs = %+v, result = %+v", got.Tabs, result)
			}
			if first := got.Tabs[0].Data.Rows[0]; !slices.Equal(first, tc.first) {
				t.Errorf("first row = %q, want %q", first, tc.first)
			}

			after, err := os.ReadDir(filepath.Join(f.root, "books"))
			if err != nil {
				t.Fatal(err)
			}
			if len(after) != len(before) {
				t.Errorf("a preview stored something: %d entries, then %d", len(before), len(after))
			}
		})
	}
}

func TestPreviewSheetRefusesBeforeWriting(t *testing.T) {
	f := newXlsxFixture(t, "budget.xlsx")
	for _, fake := range []string{"fake.xlsx", "fake.ods", "fake.xls"} {
		writeSeed(t, f.root, fake, []byte("plain text"))
	}

	for name, tc := range map[string]struct {
		filePath string
		want     any
	}{
		"fake xlsx":  {"fake.xlsx", new(*fileutil.UnsupportedError)},
		"fake ods":   {"fake.ods", new(*fileutil.UnsupportedError)},
		"fake xls":   {"fake.xls", new(*fileutil.UnsupportedError)},
		"not a book": {"notes.txt", new(*fileutil.UnsupportedError)},
		"missing":    {"missing.ods", new(*fileutil.NotFoundError)},
	} {
		var out bytes.Buffer
		_, err := fileutil.PreviewSheet(previewSheetParams(f, tc.filePath, &out))
		if err == nil || !errors.As(err, tc.want) {
			t.Errorf("%s: err = %v, want %T", name, err, tc.want)
		}
		if out.Len() != 0 {
			t.Errorf("%s: a refusal wrote %q", name, out.String())
		}
	}
}
