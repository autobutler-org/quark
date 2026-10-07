package v0_files_test

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"image"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// writePptx seeds a .pptx at rel: one slide with a picture, and one with
// notes.
func writePptx(t *testing.T, filesDir, rel string) {
	t.Helper()
	var pic bytes.Buffer
	if err := png.Encode(&pic, image.NewGray(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(`{"schemaVersion":1,"title":"Talk","slides":[
			{"id":"s1","elements":[{"id":"a","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"x.png"}]},
			{"id":"s2","elements":[],"notes":"Thanks"}]}`),
		Out: &out,
		OpenImage: func(string) (io.ReadCloser, int64, error) {
			return io.NopCloser(bytes.NewReader(pic.Bytes())), int64(pic.Len()), nil
		},
	}); err != nil {
		t.Fatal(err)
	}
	seedFile(t, filesDir, rel, out.Bytes())
}

// importResponse decodes a successful import.
func importResponse(t *testing.T, w *httptest.ResponseRecorder) v0_files.ImportPptxJSON {
	t.Helper()
	if w.Code != http.StatusOK {
		t.Fatalf("import = %d: %s", w.Code, w.Body.String())
	}
	var got v0_files.ImportPptxJSON
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	return got
}

func TestImportPptx_WritesAQslideBesideThePresentation(t *testing.T) {
	h := newAccessHarness(t, true)
	writePptx(t, h.filesDir, "shared/Talk.pptx")

	got := importResponse(t, h.post("/api/v0/files/import/pptx?filePath=shared/Talk.pptx"))
	if got.Path != "shared/Talk.qslide" || got.MediaDir != "shared/Talk_media" || got.Slides != 2 ||
		got.Pictures != 1 || got.Warnings == nil || len(got.Warnings) != 0 {
		t.Errorf("import = %+v", got)
	}
	if names, want := h.names(t, "shared"), []string{"Talk.pptx", "Talk.qslide", "Talk_media"}; !slices.Equal(names, want) {
		t.Errorf("folder = %v, want %v", names, want)
	}
	if names := h.names(t, "shared/Talk_media"); !slices.Equal(names, []string{"image1.png"}) {
		t.Errorf("media = %v", names)
	}

	// A second import keeps the first.
	again := importResponse(t, h.post("/api/v0/files/import/pptx?filePath=shared/Talk.pptx"))
	if again.Path != "shared/Talk_(1).qslide" {
		t.Errorf("second import = %+v", again)
	}
}

func TestImportPptx_WritesIntoTheFolderAskedFor(t *testing.T) {
	h := newAccessHarness(t, true)
	writePptx(t, h.filesDir, "inbox/Talk.pptx")

	got := importResponse(t, h.post("/api/v0/files/import/pptx?filePath=inbox/Talk.pptx&rootDir=decks"))
	if got.Path != "decks/Talk.qslide" || got.MediaDir != "decks/Talk_media" {
		t.Errorf("import = %+v", got)
	}
	if names := h.names(t, "inbox"); !slices.Equal(names, []string{"Talk.pptx"}) {
		t.Errorf("the source folder changed: %v", names)
	}
	// The files root, asked for by name.
	root := importResponse(t, h.post("/api/v0/files/import/pptx?filePath=inbox/Talk.pptx&rootDir="))
	if root.Path != "Talk.qslide" {
		t.Errorf("import to the root = %+v", root)
	}
}

func TestImportPptx_ReportsWhatItLeftOut(t *testing.T) {
	h := newAccessHarness(t, true)
	writePptx(t, h.filesDir, "Talk.pptx")
	// Swap the picture for a format the editor cannot show.
	writePptxWithMedia(t, h.filesDir, "Talk.pptx", "\x01\x00\x00\x00 an EMF, say")

	got := importResponse(t, h.post("/api/v0/files/import/pptx?filePath=Talk.pptx"))
	if len(got.Warnings) != 1 || got.Warnings[0].Slide != 1 || got.MediaDir != "" || got.Pictures != 0 {
		t.Errorf("import = %+v", got)
	}
}

func TestImportPptx_RejectsBadRequests(t *testing.T) {
	h := newAccessHarness(t, true)
	writeFixture(t, h.filesDir, "notes.txt")
	seedFile(t, h.filesDir, "Broken.pptx", []byte("not a zip"))

	expectCodes(t, http.StatusBadRequest, map[string]*httptest.ResponseRecorder{
		"no path":      h.post("/api/v0/files/import/pptx"),
		"not a pptx":   h.post("/api/v0/files/import/pptx?filePath=notes.txt"),
		"broken pptx":  h.post("/api/v0/files/import/pptx?filePath=Broken.pptx"),
		"climbing out": h.post("/api/v0/files/import/pptx?filePath=Broken.pptx&rootDir=../x"),
	})
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"missing": h.post("/api/v0/files/import/pptx?filePath=Missing.pptx"),
	})
	if names, want := h.names(t, ""), []string{"Broken.pptx", "notes.txt"}; !slices.Equal(names, want) {
		t.Errorf("a failed import left files behind: %v", names)
	}
}

func TestImportPptx_NeedsReadOnThePresentationAndWriteOnTheFolder(t *testing.T) {
	h := newAccessHarness(t, false)
	writePptx(t, h.filesDir, "shared/Talk.pptx")
	writePptx(t, h.filesDir, "other/Talk.pptx")
	h.grant(t, "shared", accessutil.Read)
	h.grant(t, "mine", accessutil.Write)

	expectCodes(t, http.StatusForbidden, map[string]*httptest.ResponseRecorder{
		"read-only folder": h.post("/api/v0/files/import/pptx?filePath=shared/Talk.pptx"),
	})
	expectCodes(t, http.StatusNotFound, map[string]*httptest.ResponseRecorder{
		"unreadable presentation": h.post("/api/v0/files/import/pptx?filePath=other/Talk.pptx&rootDir=mine"),
	})

	got := importResponse(t, h.post("/api/v0/files/import/pptx?filePath=shared/Talk.pptx&rootDir=mine"))
	if got.Path != "mine/Talk.qslide" {
		t.Errorf("import = %+v", got)
	}
	// The caller owns what the import created.
	levels := h.levels(t)
	for _, p := range []string{"mine/Talk.qslide", "mine/Talk_media"} {
		if levels[accessutil.Canonical(p)] != accessutil.Owner.String() {
			t.Errorf("%s: level %q, want owner (rows %v)", p, levels[accessutil.Canonical(p)], levels)
		}
	}
}

// writePptxWithMedia rewrites the .pptx at rel with its one picture's bytes
// replaced by media.
func writePptxWithMedia(t *testing.T, filesDir, rel, media string) {
	t.Helper()
	full := filepath.Join(filesDir, filepath.FromSlash(rel))
	body, err := os.ReadFile(full)
	if err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for _, f := range zr.File {
		if f.Name != "ppt/media/image1.png" {
			if err := zw.Copy(f); err != nil {
				t.Fatal(err)
			}
			continue
		}
		w, err := zw.Create(f.Name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, media); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	seedFile(t, filesDir, rel, out.Bytes())
}
