package v0_files_test

import (
	"archive/zip"
	"bytes"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
)

// seedFile writes body at rel under filesDir.
func seedFile(t *testing.T, filesDir, rel string, body []byte) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, body, 0o644); err != nil {
		t.Fatal(err)
	}
}

// writeQslide seeds a two-slide .qslide at rel whose pictures are
// shared/dog.png and other/cat.png, and both pictures.
func writeQslide(t *testing.T, filesDir, rel string) {
	t.Helper()
	var pic bytes.Buffer
	if err := png.Encode(&pic, image.NewGray(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	seedFile(t, filesDir, "shared/dog.png", pic.Bytes())
	seedFile(t, filesDir, "other/cat.png", pic.Bytes())
	seedFile(t, filesDir, rel, []byte(`{"schemaVersion":1,"title":"Talk","slides":[
		{"id":"s1","elements":[
			{"id":"a","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"shared/dog.png"},
			{"id":"b","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"other/cat.png"}]},
		{"id":"s2","elements":[],"notes":"Thanks"}]}`))
}

// pptxParts lists the downloaded presentation's part names.
func pptxParts(t *testing.T, w *httptest.ResponseRecorder) []string {
	t.Helper()
	body := w.Body.Bytes()
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("the export is not a presentation: %v", err)
	}
	var names []string
	for _, f := range zr.File {
		names = append(names, f.Name)
	}
	return names
}

func TestExportPptx_StreamsThePresentationAsADownload(t *testing.T) {
	h := newAccessHarness(t, true)
	writeQslide(t, h.filesDir, "shared/Talk.qslide")

	w := h.get("/api/v0/files/export/pptx?filePath=shared/Talk.qslide")
	if w.Code != http.StatusOK {
		t.Fatalf("export = %d: %s", w.Code, w.Body.String())
	}
	if got := w.Header().Get("Content-Type"); got != "application/vnd.openxmlformats-officedocument.presentationml.presentation" {
		t.Errorf("Content-Type = %q", got)
	}
	if got := w.Header().Get("Content-Disposition"); got != `attachment; filename=Talk.pptx` {
		t.Errorf("Content-Disposition = %q", got)
	}
	parts := pptxParts(t, w)
	for _, want := range []string{
		"ppt/presentation.xml", "ppt/slides/slide1.xml", "ppt/slides/slide2.xml",
		"ppt/notesSlides/notesSlide2.xml", "ppt/media/image1.png", "ppt/media/image2.png",
	} {
		if !slices.Contains(parts, want) {
			t.Errorf("the presentation lacks %s: %v", want, parts)
		}
	}
	// Export only reads: the folder holds what it held.
	if got, want := h.names(t, "shared"), []string{"Talk.qslide", "dog.png"}; !slices.Equal(got, want) {
		t.Errorf("folder after export = %v, want %v", got, want)
	}
}

func TestExportPptx_RejectsBadRequests(t *testing.T) {
	h := newAccessHarness(t, true)
	writeFixture(t, h.filesDir, "notes.txt")
	writeFixture(t, h.filesDir, "Broken.qslide")

	bad := map[string]*httptest.ResponseRecorder{
		"no path":       h.get("/api/v0/files/export/pptx"),
		"not a qslide":  h.get("/api/v0/files/export/pptx?filePath=notes.txt"),
		"broken qslide": h.get("/api/v0/files/export/pptx?filePath=Broken.qslide"),
	}
	missing := map[string]*httptest.ResponseRecorder{
		"missing": h.get("/api/v0/files/export/pptx?filePath=Missing.qslide"),
	}
	expectCodes(t, http.StatusBadRequest, bad)
	expectCodes(t, http.StatusNotFound, missing)
	// A failure is answered as JSON, not as a presentation attachment.
	for name, w := range bad {
		if got := w.Header().Get("Content-Disposition"); got != "" {
			t.Errorf("%s: Content-Disposition = %q", name, got)
		}
		if got := w.Header().Get("Content-Type"); !strings.HasPrefix(got, "application/json") {
			t.Errorf("%s: Content-Type = %q", name, got)
		}
	}
}

func TestExportPptx_NeedsReadAccessAndEmbedsOnlyReadablePictures(t *testing.T) {
	h := newAccessHarness(t, false)
	writeQslide(t, h.filesDir, "shared/Talk.qslide")
	h.grant(t, "shared", accessutil.Read)

	w := h.get("/api/v0/files/export/pptx?filePath=shared/Talk.qslide")
	if w.Code != http.StatusOK {
		t.Fatalf("export in a read share = %d: %s", w.Code, w.Body.String())
	}
	// other/cat.png is outside the share, so it is a placeholder.
	var media []string
	for _, name := range pptxParts(t, w) {
		if strings.HasPrefix(name, "ppt/media/") {
			media = append(media, name)
		}
	}
	if !slices.Equal(media, []string{"ppt/media/image1.png"}) {
		t.Errorf("media = %v, want only the shared picture", media)
	}
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"no share": h.get("/api/v0/files/export/pptx?filePath=other/Talk.qslide"),
	})
}
