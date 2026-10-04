package v0_files_test

import (
	"archive/zip"
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// writeQsheet seeds a two-tab .qsheet at rel under filesDir.
func writeQsheet(t *testing.T, filesDir, rel string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	body := `{"tabs":[{"name":"Budget","data":{"rows":[["Rent","1200"]]}},{"name":"Notes","data":{"rows":[["hi"]]}}]}`
	if err := os.WriteFile(full, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// workbookSheets reads the downloaded workbook and returns its workbook part.
func workbookSheets(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	body := w.Body.Bytes()
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("the export is not a workbook: %v", err)
	}
	f, err := zr.Open("xl/workbook.xml")
	if err != nil {
		t.Fatalf("no workbook part: %v", err)
	}
	defer f.Close()
	part, err := io.ReadAll(f)
	if err != nil {
		t.Fatal(err)
	}
	return string(part)
}

func TestExportXlsx_StreamsEveryTabAsADownload(t *testing.T) {
	h := newAccessHarness(t, true)
	writeQsheet(t, h.filesDir, "money/Budget.qsheet")

	w := h.get("/api/v0/files/export/xlsx?filePath=money/Budget.qsheet")
	if w.Code != http.StatusOK {
		t.Fatalf("export = %d: %s", w.Code, w.Body.String())
	}
	if got := w.Header().Get("Content-Type"); got != "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" {
		t.Errorf("Content-Type = %q", got)
	}
	if got := w.Header().Get("Content-Disposition"); got != `attachment; filename=Budget.xlsx` {
		t.Errorf("Content-Disposition = %q", got)
	}
	book := workbookSheets(t, w)
	if !strings.Contains(book, `name="Budget"`) || !strings.Contains(book, `name="Notes"`) {
		t.Errorf("workbook part = %s", book)
	}
	// Export only reads: the folder holds the sheet and nothing else.
	if got, want := h.names(t, "money"), []string{"Budget.qsheet"}; !slices.Equal(got, want) {
		t.Errorf("folder after export = %v, want %v", got, want)
	}
}

func TestExportXlsx_RejectsBadRequests(t *testing.T) {
	h := newAccessHarness(t, true)
	writeFixture(t, h.filesDir, "notes.txt")
	writeFixture(t, h.filesDir, "Broken.qsheet")

	bad := map[string]*httptest.ResponseRecorder{
		"no path":       h.get("/api/v0/files/export/xlsx"),
		"not a qsheet":  h.get("/api/v0/files/export/xlsx?filePath=notes.txt"),
		"broken qsheet": h.get("/api/v0/files/export/xlsx?filePath=Broken.qsheet"),
	}
	missing := map[string]*httptest.ResponseRecorder{
		"missing": h.get("/api/v0/files/export/xlsx?filePath=Missing.qsheet"),
	}
	expectCodes(t, http.StatusBadRequest, bad)
	expectCodes(t, http.StatusNotFound, missing)
	// A failure is answered as JSON, not as a workbook attachment.
	for name, w := range bad {
		if got := w.Header().Get("Content-Disposition"); got != "" {
			t.Errorf("%s: Content-Disposition = %q", name, got)
		}
		if got := w.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/json") {
			t.Errorf("%s: Content-Type = %q", name, got)
		}
	}
}

func TestExportXlsx_NeedsOnlyReadAccess(t *testing.T) {
	h := newAccessHarness(t, false)
	writeQsheet(t, h.filesDir, "shared/Budget.qsheet")
	writeQsheet(t, h.filesDir, "other/Budget.qsheet")
	h.grant(t, "shared", accessutil.Read)

	if w := h.get("/api/v0/files/export/xlsx?filePath=shared/Budget.qsheet"); w.Code != http.StatusOK {
		t.Fatalf("export in a read share = %d: %s", w.Code, w.Body.String())
	}
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"no share": h.get("/api/v0/files/export/xlsx?filePath=other/Budget.qsheet"),
	})
}
