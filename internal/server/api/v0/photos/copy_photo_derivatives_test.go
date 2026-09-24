package v0_photos_test

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
)

// TestCopyPhoto_CopiesDerivatives: a copy of a photo keeps the thumbnail its
// client uploaded, so a HEIC copy still shows one.
func TestCopyPhoto_CopiesDerivatives(t *testing.T) {
	h := newPhotoHarness(t)
	source := filepath.Join(h.filesDir, "shared", "a.jpg")
	thumb := derivativeutil.Path(source, derivativeutil.KindThumbnail)
	if err := os.MkdirAll(filepath.Dir(thumb), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(thumb, []byte("jpeg"), 0o600); err != nil {
		t.Fatal(err)
	}

	w := h.do(http.MethodPost, "/api/v0/photos/copy", `{"relPath":"shared/a.jpg"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("copy = %d: %s", w.Code, w.Body.String())
	}
	var resp struct {
		RelPath string `json:"relPath"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	copied := filepath.Join(h.filesDir, filepath.FromSlash(resp.RelPath))
	if _, err := os.Stat(derivativeutil.Path(copied, derivativeutil.KindThumbnail)); err != nil {
		t.Errorf("the copy at %s has no thumbnail: %v", resp.RelPath, err)
	}
}
