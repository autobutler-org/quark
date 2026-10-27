package v0_files_test

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

func TestConvertXlsx_AcceptsALegacyXls(t *testing.T) {
	h := newAccessHarness(t, false)
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "..", "pkg", "util", "xlsutil", "testdata", "libreoffice.xls"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(h.filesDir, "shared"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(h.filesDir, "shared", "budget.xls"), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	h.grant(t, "shared", accessutil.Write)

	w := h.post("/api/v0/files/convert/xlsx?filePath=shared/budget.xls")
	if w.Code != http.StatusOK {
		t.Fatalf("convert = %d: %s", w.Code, w.Body.String())
	}
	var got v0_files.ConvertXlsxJSON
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Path != "shared/budget.qsheet" || got.Tabs != 3 {
		t.Errorf("response = %+v", got)
	}
	sheet, err := os.ReadFile(filepath.Join(h.filesDir, "shared", "budget.qsheet"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(sheet), `"Budget"`) {
		t.Errorf(".qsheet = %s", sheet)
	}

	if err := os.WriteFile(filepath.Join(h.filesDir, "shared", "fake.ods"), []byte("plain text"), 0o644); err != nil {
		t.Fatal(err)
	}
	if w := h.post("/api/v0/files/convert/xlsx?filePath=shared/fake.ods"); w.Code != http.StatusBadRequest {
		t.Errorf("a fake .ods: status = %d, want 400: %s", w.Code, w.Body.String())
	}
}
