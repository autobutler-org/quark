package v0_previews_test

import (
	"bytes"
	"encoding/json"
	"image"
	"image/png"
	"io"
	"net/http"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// writePptx exports a one-slide deck showing one picture as a .pptx at rel.
func (h harness) writePptx(t *testing.T, rel string) {
	t.Helper()
	var pic bytes.Buffer
	if err := png.Encode(&pic, image.NewGray(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	const deck = `{"schemaVersion":1,"title":"Talk","slides":[{"id":"s1","elements":[` +
		`{"id":"a","type":"image","frame":{"x":0,"y":0,"width":10,"height":10},"source":"dog.png"}]}]}`
	var out bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(deck),
		Out:    &out,
		OpenImage: func(string) (io.ReadCloser, int64, error) {
			return io.NopCloser(bytes.NewReader(pic.Bytes())), int64(pic.Len()), nil
		},
	}); err != nil {
		t.Fatal(err)
	}
	h.writeFile(t, rel, out.Bytes())
}

func TestPreviewSlides_StreamsQslideWithPartReferences(t *testing.T) {
	h := newHarness(t)
	h.writePptx(t, "shared/talk.pptx")

	w := h.get("slides", map[string]string{"filePath": "shared/talk.pptx"})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type = %q", ct)
	}
	if got := w.Header().Get("X-Quark-Import-Warnings"); got != "0" {
		t.Errorf("warnings header = %q, want 0", got)
	}
	if got := w.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Errorf("X-Content-Type-Options = %q, want nosniff", got)
	}
	var deck struct {
		Slides []struct{ Elements []struct{ Source string } }
	}
	if err := json.Unmarshal(w.Body.Bytes(), &deck); err != nil {
		t.Fatalf("not JSON: %v: %s", err, w.Body.String())
	}
	if len(deck.Slides) != 1 || len(deck.Slides[0].Elements) != 1 {
		t.Fatalf("deck = %s", w.Body.String())
	}
	source := deck.Slides[0].Elements[0].Source
	part, ok := strings.CutPrefix(source, "part:")
	if !ok {
		t.Fatalf("picture source = %q, want a part: reference", source)
	}

	img := h.get("part", map[string]string{"filePath": "shared/talk.pptx", "part": part})
	if img.Code != http.StatusOK || img.Header().Get("Content-Type") != "image/png" {
		t.Errorf("part %q: status %d, %q", part, img.Code, img.Header().Get("Content-Type"))
	}
}

func TestPreviewSlides_Refusals(t *testing.T) {
	h := newHarness(t)
	h.writePptx(t, "other/secret.pptx")
	h.writeFile(t, "shared/fake.pptx", []byte("this is plain text"))
	h.writeDocx(t, "shared/report.docx", pictureBody)

	for name, tc := range map[string]struct {
		filePath string
		want     int
	}{
		"no access":          {"other/secret.pptx", http.StatusNotFound},
		"missing":            {"shared/missing.pptx", http.StatusNotFound},
		"not what it claims": {"shared/fake.pptx", http.StatusBadRequest},
		"not a presentation": {"shared/report.docx", http.StatusBadRequest},
		"no filePath":        {"", http.StatusBadRequest},
	} {
		w := h.get("slides", map[string]string{"filePath": tc.filePath})
		if w.Code != tc.want {
			t.Errorf("%s: status = %d, want %d: %s", name, w.Code, tc.want, w.Body.String())
		}
	}
}
