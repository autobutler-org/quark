package fileutil_test

import (
	"archive/zip"
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// twoTabSheet is a .qsheet as the editor saves it, with a formatted cell.
const twoTabSheet = `{"tabs":[
	{"name":"Budget","data":{"rows":[["Item","Cost"],["Rent","1200"]]},"formats":[{"row":0,"col":0,"bold":true}]},
	{"name":"Notes","data":{"rows":[["hello"]]}}
]}`

// newExportFixture is a files namespace holding name with body in it.
func newExportFixture(t *testing.T, name, body string) (string, fileutil.ExportXlsxParams) {
	t.Helper()
	root := t.TempDir()
	full := filepath.Join(root, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(full, []byte(body), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}
	fsys, err := vfs.NewLocalVFS(root, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS failed: %v", err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files", MountPath: "/"}, fsys); err != nil {
		t.Fatalf("Register failed: %v", err)
	}
	return root, fileutil.ExportXlsxParams{
		Ctx:      context.Background(),
		Registry: registry,
		FilePath: name,
	}
}

// workbookPart reads a written workbook and returns its workbook part.
func workbookPart(t *testing.T, book []byte) string {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(book), int64(len(book)))
	if err != nil {
		t.Fatalf("not a zip: %v", err)
	}
	f, err := zr.Open("xl/workbook.xml")
	if err != nil {
		t.Fatalf("no workbook part: %v", err)
	}
	defer f.Close()
	body, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("read workbook part: %v", err)
	}
	return string(body)
}

func TestExportQsheetToXlsxStreamsTheWorkbookAndWritesNothingBeside(t *testing.T) {
	root, params := newExportFixture(t, "money/Budget.qsheet", twoTabSheet)
	var out bytes.Buffer
	params.Out = &out

	result, err := fileutil.ExportQsheetToXlsx(params)
	if err != nil {
		t.Fatalf("ExportQsheetToXlsx: %v", err)
	}
	if got := fileutil.XlsxExportName(params.FilePath); got != "Budget.xlsx" {
		t.Errorf("XlsxExportName = %q", got)
	}
	if result.Tabs != 2 || result.Rows != 3 || result.Cells != 5 {
		t.Errorf("counts = %+v", result)
	}
	book := workbookPart(t, out.Bytes())
	if !strings.Contains(book, `name="Budget"`) || !strings.Contains(book, `name="Notes"`) {
		t.Errorf("workbook part = %s", book)
	}
	// Export is read-only: the folder holds the sheet and nothing else.
	entries, err := os.ReadDir(filepath.Join(root, "money"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "Budget.qsheet" {
		t.Errorf("folder after export = %v", entries)
	}
}

func TestExportQsheetToXlsxRejectsOtherExtensions(t *testing.T) {
	_, params := newExportFixture(t, "notes.txt", twoTabSheet)
	params.Out = io.Discard
	_, err := fileutil.ExportQsheetToXlsx(params)
	var unsupported *fileutil.UnsupportedError
	if !errors.As(err, &unsupported) {
		t.Fatalf("err = %v, want UnsupportedError", err)
	}
}

func TestExportQsheetToXlsxWritesNothingForABrokenSheet(t *testing.T) {
	for name, body := range map[string]string{
		"truncated":   `{"tabs":[{"name":"S","data":{"rows":[["1"`,
		"not json":    `hello`,
		"wrong shape": `{"tabs":[{"name":"S","data":{"rows":"x"}}]}`,
	} {
		t.Run(name, func(t *testing.T) {
			_, params := newExportFixture(t, "Broken.qsheet", body)
			var out bytes.Buffer
			params.Out = &out

			_, err := fileutil.ExportQsheetToXlsx(params)
			var unsupported *fileutil.UnsupportedError
			if !errors.As(err, &unsupported) {
				t.Fatalf("err = %v, want UnsupportedError", err)
			}
			if out.Len() != 0 {
				t.Errorf("wrote %d bytes before failing", out.Len())
			}
		})
	}
}

func TestExportQsheetToXlsxReportsAMissingSheet(t *testing.T) {
	_, params := newExportFixture(t, "Budget.qsheet", twoTabSheet)
	params.FilePath = "Missing.qsheet"
	params.Out = io.Discard

	_, err := fileutil.ExportQsheetToXlsx(params)
	var missing *fileutil.NotFoundError
	if !errors.As(err, &missing) {
		t.Fatalf("err = %v, want NotFoundError", err)
	}
}
