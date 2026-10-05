package pptxutil

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"
)

// decodeOut reads a .qslide into the import's output types, each element by
// its type, so it can be written back and compared.
func decodeOut(t *testing.T, body []byte) outPresentation {
	t.Helper()
	var raw struct {
		outPresentation
		Slides []struct {
			outSlide
			Elements []json.RawMessage `json:"elements"`
		} `json:"slides"`
	}
	dec := json.NewDecoder(bytes.NewReader(body))
	if err := dec.Decode(&raw); err != nil {
		t.Fatal(err)
	}
	p := raw.outPresentation
	p.Slides = []outSlide{}
	for _, rs := range raw.Slides {
		slide := rs.outSlide
		slide.Elements = decodeElements(t, rs.Elements)
		p.Slides = append(p.Slides, slide)
	}
	return p
}

func decodeElements(t *testing.T, raws []json.RawMessage) []outElement {
	t.Helper()
	out := []outElement{}
	for _, raw := range raws {
		var head struct {
			Type     string            `json:"type"`
			Children []json.RawMessage `json:"children"`
		}
		strict := func(v any) {
			dec := json.NewDecoder(bytes.NewReader(raw))
			dec.DisallowUnknownFields()
			if err := dec.Decode(v); err != nil {
				t.Fatalf("%s: %v", raw, err)
			}
		}
		if err := json.Unmarshal(raw, &head); err != nil {
			t.Fatal(err)
		}
		switch head.Type {
		case typeText:
			var e outText
			strict(&e)
			out = append(out, e)
		case typeShape:
			var e outShape
			strict(&e)
			out = append(out, e)
		case typeImage:
			var e outImage
			strict(&e)
			out = append(out, e)
		case typeLine:
			var e outLine
			strict(&e)
			out = append(out, e)
		case typeGroup:
			var e struct {
				outGroup
				Children []json.RawMessage `json:"children"`
			}
			strict(&e)
			e.outGroup.Children = decodeElements(t, e.Children)
			out = append(out, e.outGroup)
		default:
			t.Fatalf("unexpected element type %q", head.Type)
		}
	}
	return out
}

// TestImportTypesMirrorTheCodec reads quark_slides' golden fixture into the
// import's types and streams it back out: the bytes must be the fixture's, so
// a .qslide an import writes is what QslideCodec.encode would have written.
func TestImportTypesMirrorTheCodec(t *testing.T) {
	golden, err := os.ReadFile("../../../packages/quark_slides/test/fixtures/sample.qslide")
	if err != nil {
		t.Fatal(err)
	}
	p := decodeOut(t, golden)

	var streamed bytes.Buffer
	w := &qslideWriter{w: &streamed}
	if err := w.header(p.Title, p.Size); err != nil {
		t.Fatal(err)
	}
	for _, slide := range p.Slides {
		if err := w.slide(slide); err != nil {
			t.Fatal(err)
		}
	}
	if err := w.close(); err != nil {
		t.Fatal(err)
	}
	// The stream writes no theme, which an import never has; the fixture's is
	// the one line it adds.
	want := strings.Replace(string(golden), "  \"theme\": \"themes/default\",\n", "", 1)
	if streamed.String() != want {
		t.Errorf("streamed .qslide differs from the codec's:\n%s\nwant:\n%s", streamed.String(), want)
	}

	// The whole document marshals the same way the stream writes it.
	whole, err := marshalIndented(p, "")
	if err != nil {
		t.Fatal(err)
	}
	if whole+"\n" != string(golden) {
		t.Errorf("marshaled .qslide differs from the codec's:\n%s", whole)
	}
}

func TestImportStreamsAnEmptyDeckAsTheCodecWould(t *testing.T) {
	var streamed bytes.Buffer
	w := &qslideWriter{w: &streamed}
	if err := w.header("", outSize{Width: 1920, Height: 1080}); err != nil {
		t.Fatal(err)
	}
	if err := w.close(); err != nil {
		t.Fatal(err)
	}
	whole, _ := marshalIndented(outPresentation{SchemaVersion: 1, Size: outSize{1920, 1080}, Slides: []outSlide{}}, "")
	if streamed.String() != whole+"\n" {
		t.Errorf("empty deck = %q, want %q", streamed.String(), whole+"\n")
	}
}

// TestImportChargesEveryPartAgainstOneBudget reads two parts past what is
// left of the package's budget; the second fails, whatever each declares.
func TestImportChargesEveryPartAgainstOneBudget(t *testing.T) {
	var b bytes.Buffer
	zw := zip.NewWriter(&b)
	for _, name := range []string{"a.xml", "b.xml"} {
		w, _ := zw.Create(name)
		_, _ = w.Write([]byte("<a>" + strings.Repeat(" ", 600) + "</a>"))
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	a, err := openArchive(bytes.NewReader(b.Bytes()), int64(b.Len()))
	if err != nil {
		t.Fatal(err)
	}
	a.remaining = 1000
	var v struct{}
	if err := a.decodeXML("a.xml", &v); err != nil {
		t.Fatalf("first part: %v", err)
	}
	if err := a.decodeXML("b.xml", &v); !errors.Is(err, ErrTooLarge) {
		t.Fatalf("second part = %v, want ErrTooLarge", err)
	}
}

func TestImportResolvesRelationshipTargetsInsideThePackage(t *testing.T) {
	for _, c := range []struct {
		source, target, want string
		ok                   bool
	}{
		{"ppt/slides/slide1.xml", "../media/image1.png", "ppt/media/image1.png", true},
		{"ppt/slides/slide1.xml", "/ppt/media/a%20b.png", "ppt/media/a b.png", true},
		{"ppt/presentation.xml", "slides/slide1.xml", "ppt/slides/slide1.xml", true},
		{"", "ppt/presentation.xml", "ppt/presentation.xml", true},
		{"ppt/slides/slide1.xml", "../../../etc/passwd", "", false},
		{"ppt/slides/slide1.xml", "..\\media\\x.png", "", false},
		{"ppt/slides/slide1.xml", "", "", false},
	} {
		got, ok := resolveTarget(c.source, c.target)
		if got != c.want || ok != c.ok {
			t.Errorf("resolveTarget(%q, %q) = %q, %v; want %q, %v", c.source, c.target, got, ok, c.want, c.ok)
		}
	}
}
