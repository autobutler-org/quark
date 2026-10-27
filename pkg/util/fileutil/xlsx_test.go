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
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// seedWorkbook writes a minimal but complete .xlsx into root and returns its
// files-relative path. The sheet holds one header row and one data row.
func seedWorkbook(t *testing.T, root, name string) string {
	t.Helper()
	return seedParts(t, root, name, workbookParts())
}

// workbookParts is the one-sheet workbook the fixtures convert.
func workbookParts() map[string]string {
	return map[string]string{
		"_rels/.rels": `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>` +
			`</Relationships>`,
		"xl/workbook.xml": `<?xml version="1.0"?><workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` +
			`<sheets><sheet name="Ledger" sheetId="1" r:id="rId1"/></sheets></workbook>`,
		"xl/_rels/workbook.xml.rels": `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>` +
			`</Relationships>`,
		"xl/sharedStrings.xml": `<sst><si><t>Item</t></si><si><t>Coffee</t></si></sst>`,
		"xl/worksheets/sheet1.xml": `<?xml version="1.0"?><worksheet><sheetData>` +
			`<row r="1"><c r="A1" t="s"><v>0</v></c></row>` +
			`<row r="2"><c r="A2" t="s"><v>1</v></c></row>` +
			`</sheetData></worksheet>`,
	}
}

// seedParts packages the given parts as an .xlsx at name under root.
func seedParts(t *testing.T, root, name string, parts map[string]string) string {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for partName, body := range parts {
		w, err := zw.Create(partName)
		if err != nil {
			t.Fatalf("create %s: %v", partName, err)
		}
		if _, err := w.Write([]byte(body)); err != nil {
			t.Fatalf("write %s: %v", partName, err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("close zip: %v", err)
	}

	full := filepath.Join(root, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(full, buf.Bytes(), 0o600); err != nil {
		t.Fatalf("seed workbook: %v", err)
	}
	return name
}

// xlsxFixture is a files namespace with a workbook already in it.
type xlsxFixture struct {
	root   string
	params fileutil.ConvertXlsxParams
}

func newXlsxFixture(t *testing.T, workbook string) xlsxFixture {
	t.Helper()
	root := t.TempDir()
	path := seedWorkbook(t, root, workbook)

	fsys, err := vfs.NewLocalVFS(root, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS failed: %v", err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files", MountPath: "/"}, fsys); err != nil {
		t.Fatalf("Register failed: %v", err)
	}

	return xlsxFixture{
		root: root,
		params: fileutil.ConvertXlsxParams{
			Ctx:      context.Background(),
			Registry: registry,
			EventBus: eventbus.New(),
			FilePath: path,
		},
	}
}

// rowsOf reads a written .qsheet back as the grid the editor would load.
func rowsOf(t *testing.T, root, relPath string) [][]string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(relPath)))
	if err != nil {
		t.Fatalf("read %s: %v", relPath, err)
	}
	var doc struct {
		Tabs []struct {
			Name string `json:"name"`
			Data struct {
				Rows [][]string `json:"rows"`
			} `json:"data"`
		} `json:"tabs"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("%s is not a valid .qsheet: %v\n%s", relPath, err, raw)
	}
	if len(doc.Tabs) != 1 {
		t.Fatalf("got %d tabs, want 1", len(doc.Tabs))
	}
	return doc.Tabs[0].Data.Rows
}

// leftovers lists the temporary files a conversion should never leave behind.
func leftovers(t *testing.T, root string) []string {
	t.Helper()
	var found []string
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatalf("read dir: %v", err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".") {
			found = append(found, e.Name())
		}
	}
	return found
}

func TestConvertXlsxToQsheetWritesASiblingSheet(t *testing.T) {
	f := newXlsxFixture(t, "books/budget.xlsx")

	result, err := fileutil.ConvertXlsxToQsheet(f.params)
	if err != nil {
		t.Fatalf("ConvertXlsxToQsheet: %v", err)
	}
	if result.Path != "books/budget.qsheet" {
		t.Errorf("Path = %q, want books/budget.qsheet", result.Path)
	}
	if result.Tabs != 1 || result.Rows != 2 || result.Cells != 2 {
		t.Errorf("result = %+v, want 1 tab, 2 rows, 2 cells", result)
	}

	rows := rowsOf(t, f.root, result.Path)
	if len(rows) != 2 || rows[0][0] != "Item" || rows[1][0] != "Coffee" {
		t.Errorf("rows = %v, want [[Item] [Coffee]]", rows)
	}

	// The workbook is converted, not consumed.
	if _, err := os.Stat(filepath.Join(f.root, "books", "budget.xlsx")); err != nil {
		t.Errorf("the original workbook is gone: %v", err)
	}
	if left := leftovers(t, filepath.Join(f.root, "books")); len(left) != 0 {
		t.Errorf("conversion left %v behind", left)
	}
}

func TestConvertXlsxToQsheetRefusesToClobber(t *testing.T) {
	f := newXlsxFixture(t, "budget.xlsx")
	existing := filepath.Join(f.root, "budget.qsheet")
	if err := os.WriteFile(existing, []byte(`{"tabs":[{"name":"Mine","data":{"rows":[["keep me"]]}}]}`), 0o600); err != nil {
		t.Fatalf("seed existing sheet: %v", err)
	}

	_, err := fileutil.ConvertXlsxToQsheet(f.params)
	if !errors.Is(err, vfs.ErrConflict) {
		t.Fatalf("err = %v, want vfs.ErrConflict", err)
	}

	rows := rowsOf(t, f.root, "budget.qsheet")
	if len(rows) != 1 || rows[0][0] != "keep me" {
		t.Errorf("the existing sheet was modified: %v", rows)
	}
	if left := leftovers(t, f.root); len(left) != 0 {
		t.Errorf("refused conversion left %v behind", left)
	}
}

func TestConvertXlsxToQsheetOverwritesWhenAsked(t *testing.T) {
	f := newXlsxFixture(t, "budget.xlsx")
	if err := os.WriteFile(filepath.Join(f.root, "budget.qsheet"),
		[]byte(`{"tabs":[{"name":"Old","data":{"rows":[["replace me"]]}}]}`), 0o600); err != nil {
		t.Fatalf("seed existing sheet: %v", err)
	}

	f.params.Overwrite = true
	if _, err := fileutil.ConvertXlsxToQsheet(f.params); err != nil {
		t.Fatalf("ConvertXlsxToQsheet: %v", err)
	}

	rows := rowsOf(t, f.root, "budget.qsheet")
	if len(rows) != 2 || rows[0][0] != "Item" {
		t.Errorf("rows = %v, want the converted workbook", rows)
	}
}

func TestConvertXlsxToQsheetRejectsOtherExtensions(t *testing.T) {
	// Anything that is not a workbook is refused rather than attempted, so the
	// client can keep offering the download.
	for _, name := range []string{"slides.pptx", "notes.txt", "sheet.csv"} {
		t.Run(name, func(t *testing.T) {
			f := newXlsxFixture(t, "budget.xlsx")
			f.params.FilePath = name

			_, err := fileutil.ConvertXlsxToQsheet(f.params)
			var unsupported *fileutil.UnsupportedError
			if !errors.As(err, &unsupported) {
				t.Fatalf("err = %v, want UnsupportedError", err)
			}
		})
	}
}

func TestConvertXlsxToQsheetLeavesNothingBehindWhenTheWorkbookIsBroken(t *testing.T) {
	// The conversion streams into the destination, so a workbook that fails
	// has already had bytes written for it. Nothing may survive that: no
	// .qsheet, and no temporary file either.
	f := newXlsxFixture(t, "broken.xlsx")
	if err := os.WriteFile(filepath.Join(f.root, "broken.xlsx"),
		[]byte("this is not a spreadsheet at all"), 0o600); err != nil {
		t.Fatalf("overwrite workbook: %v", err)
	}

	_, err := fileutil.ConvertXlsxToQsheet(f.params)
	var unsupported *fileutil.UnsupportedError
	if !errors.As(err, &unsupported) {
		t.Fatalf("err = %v, want UnsupportedError", err)
	}

	if _, err := os.Stat(filepath.Join(f.root, "broken.qsheet")); !os.IsNotExist(err) {
		t.Errorf("a .qsheet was left behind for a workbook that did not convert")
	}
	if left := leftovers(t, f.root); len(left) != 0 {
		t.Errorf("failed conversion left %v behind", left)
	}
}

func TestConvertXlsxToQsheetLeavesNothingBehindWhenALaterSheetFails(t *testing.T) {
	// The failure that actually strands a partial document: the first sheet
	// measures, converts and is written, and only then does the second turn
	// out to be malformed. Whatever reached the destination has to go.
	f := newXlsxFixture(t, "two_sheets.xlsx")
	parts := workbookParts()
	parts["xl/workbook.xml"] = `<?xml version="1.0"?><workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` +
		`<sheets><sheet name="Good" sheetId="1" r:id="rId1"/><sheet name="Bad" sheetId="2" r:id="rId2"/></sheets></workbook>`
	parts["xl/_rels/workbook.xml.rels"] = `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
		`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>` +
		`<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>` +
		`</Relationships>`
	parts["xl/worksheets/sheet2.xml"] = `<?xml version="1.0"?><worksheet><sheetData><row r="1"><c r="A1"><v>1</v></c></row>` // never closed
	seedParts(t, f.root, "two_sheets.xlsx", parts)

	if _, err := fileutil.ConvertXlsxToQsheet(f.params); err == nil {
		t.Fatal("a workbook with a malformed sheet converted without error")
	}
	if _, err := os.Stat(filepath.Join(f.root, "two_sheets.qsheet")); !os.IsNotExist(err) {
		t.Errorf("a .qsheet was left behind for a workbook that did not convert")
	}
	if left := leftovers(t, f.root); len(left) != 0 {
		t.Errorf("failed conversion left %v behind", left)
	}
}

// bluntVFS writes straight to the destination rather than through a temporary
// file and a rename, which is how the storage-service namespace behind the
// live `files` mount behaves: a copy that fails part-way leaves a truncated
// file where it was writing. The conversion has to be safe on that namespace
// too, which is what the temporary name and the closing move are for.
type bluntVFS struct {
	*vfs.LocalVFS
	root string
}

func (b bluntVFS) Write(_ context.Context, name string, r io.Reader, _ vfs.WriteOptions) error {
	full := filepath.Join(b.root, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return err
	}
	f, err := os.Create(full)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, r)
	return err
}

func TestConvertXlsxToQsheetSurvivesANonAtomicNamespace(t *testing.T) {
	f := newXlsxFixture(t, "two_sheets.xlsx")
	parts := workbookParts()
	parts["xl/workbook.xml"] = `<?xml version="1.0"?><workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` +
		`<sheets><sheet name="Good" sheetId="1" r:id="rId1"/><sheet name="Bad" sheetId="2" r:id="rId2"/></sheets></workbook>`
	parts["xl/_rels/workbook.xml.rels"] = `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
		`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>` +
		`<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>` +
		`</Relationships>`
	parts["xl/worksheets/sheet2.xml"] = `<?xml version="1.0"?><worksheet><sheetData><row r="1"><c r="A1"><v>1</v></c></row>`
	seedParts(t, f.root, "two_sheets.xlsx", parts)

	// A .qsheet the user already has, which the failed conversion must not touch.
	if err := os.WriteFile(filepath.Join(f.root, "two_sheets.qsheet"),
		[]byte(`{"tabs":[{"name":"Mine","data":{"rows":[["keep me"]]}}]}`), 0o600); err != nil {
		t.Fatalf("seed existing sheet: %v", err)
	}

	local, err := vfs.NewLocalVFS(f.root, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS failed: %v", err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files", MountPath: "/"}, bluntVFS{LocalVFS: local, root: f.root}); err != nil {
		t.Fatalf("Register failed: %v", err)
	}
	f.params.Registry = registry
	f.params.Overwrite = true

	if _, err := fileutil.ConvertXlsxToQsheet(f.params); err == nil {
		t.Fatal("a workbook with a malformed sheet converted without error")
	}

	rows := rowsOf(t, f.root, "two_sheets.qsheet")
	if len(rows) != 1 || rows[0][0] != "keep me" {
		t.Errorf("the existing sheet was replaced by a failed conversion: %v", rows)
	}
	if left := leftovers(t, f.root); len(left) != 0 {
		t.Errorf("failed conversion left %v behind", left)
	}
}

func TestConvertXlsxToQsheetReadsOdsAndXls(t *testing.T) {
	for name, tc := range map[string]struct {
		seed     func(t *testing.T, root, name string)
		workbook string
		want     string
	}{
		"ods": {seedOds, "books/budget.ods", "Item"},
		"xls": {seedXls, "books/legacy.xls", "Item"},
	} {
		t.Run(name, func(t *testing.T) {
			f := newXlsxFixture(t, "placeholder.xlsx")
			tc.seed(t, f.root, tc.workbook)
			f.params.FilePath = tc.workbook

			result, err := fileutil.ConvertXlsxToQsheet(f.params)
			if err != nil {
				t.Fatalf("ConvertXlsxToQsheet: %v", err)
			}
			want := strings.TrimSuffix(tc.workbook, filepath.Ext(tc.workbook)) + ".qsheet"
			if result.Path != want || result.Tabs == 0 {
				t.Errorf("result = %+v, want a sheet at %s", result, want)
			}
			raw, err := os.ReadFile(filepath.Join(f.root, filepath.FromSlash(result.Path)))
			if err != nil {
				t.Fatalf("read %s: %v", result.Path, err)
			}
			if !strings.Contains(string(raw), `"`+tc.want+`"`) {
				t.Errorf("%s does not hold %q: %s", result.Path, tc.want, raw)
			}
		})
	}
}

func TestConvertXlsxToQsheetRefusesAWorkbookThatIsNotOne(t *testing.T) {
	for _, workbook := range []string{"fake.ods", "fake.xls"} {
		f := newXlsxFixture(t, "placeholder.xlsx")
		if err := os.WriteFile(filepath.Join(f.root, workbook), []byte("plain text"), 0o600); err != nil {
			t.Fatal(err)
		}
		f.params.FilePath = workbook

		_, err := fileutil.ConvertXlsxToQsheet(f.params)
		var unsupported *fileutil.UnsupportedError
		if !errors.As(err, &unsupported) {
			t.Errorf("%s: err = %v, want an UnsupportedError", workbook, err)
		}
		if left := leftovers(t, f.root); len(left) != 0 {
			t.Errorf("%s: failed conversion left %v behind", workbook, left)
		}
	}
}

func TestIsWorkbookPath(t *testing.T) {
	tests := map[string]bool{
		"budget.xlsx":       true,
		"macros.xlsm":       true,
		"BUDGET.XLSX":       true,
		"a/b/c/budget.xlsx": true,
		"legacy.xls":        true,
		"calc.ods":          true,
		"slides.pptx":       false,
		"notes.txt":         false,
		"budget":            false,
		"":                  false,
	}
	for path, want := range tests {
		if got := fileutil.IsWorkbookPath(path); got != want {
			t.Errorf("IsWorkbookPath(%q) = %v, want %v", path, got, want)
		}
	}
}
