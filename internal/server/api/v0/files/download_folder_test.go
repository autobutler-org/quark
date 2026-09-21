package v0_files_test

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// TestDownloadFolder_ZipFileName verifies a folder download names its archive
// after the folder with a .zip extension, quoted so a space survives.
func TestDownloadFolder_ZipFileName(t *testing.T) {
	engine, vfsRoot := newVFSTestEngine(t)

	dir := filepath.Join(vfsRoot, "my photos")
	if err := os.Mkdir(dir, 0755); err != nil {
		t.Fatalf("Mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("a"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v0/files/download?filePath=my%20photos", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200", w.Code)
	}
	const want = `attachment; filename="my photos.zip"`
	if got := w.Header().Get("Content-Disposition"); got != want {
		t.Errorf("Content-Disposition: got %q, want %q", got, want)
	}
	if w.Body.Len() == 0 {
		t.Error("archive body empty")
	}
}
