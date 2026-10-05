package pptxutil_test

// cspell:ignore autofit descr ffcc fmla prst srgb xfrm

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"image"
	"image/png"
	"io"
	"os"
	"path"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// sampleDeck uses every feature the export carries: a text box with every run
// style, shapes of each kind, a line arrow, pictures, a nested group,
// backgrounds and notes.
const sampleDeck = `{
  "schemaVersion": 1,
  "title": "Sample & deck",
  "size": {"width": 1920, "height": 1080},
  "slides": [
    {
      "id": "s1",
      "background": {"color": "#102030"},
      "elements": [
        {"id": "e1", "type": "text", "frame": {"x": 160, "y": 120, "width": 1600, "height": 240},
         "paragraphs": [
           {"runs": [{"text": "Hello, ", "fontSize": 72},
                     {"text": "slides", "bold": true, "italic": true, "underline": true, "strikethrough": true,
                      "fontSize": 72, "fontFamily": "Inter", "color": "#FFCC00"}],
            "align": "center"},
           {"runs": []},
           {"runs": [{"text": "Second <line>"}], "lineSpacing": 1.5, "list": "numbered"},
           {"runs": [{"text": "A bullet", "fontFamily": "serif"}], "list": "bullet", "align": "end"}
         ],
         "anchor": "middle", "autoFit": "shrink", "placeholder": "Click to add title"},
        {"id": "e2", "type": "shape", "frame": {"x": 100.5, "y": 600, "width": 400, "height": 300, "rotation": 15},
         "kind": "ellipse", "fill": "#3366FF80", "stroke": {"color": "#FFFFFF", "width": 4, "dash": "dashDot"},
         "opacity": 0.75},
        {"id": "e6", "type": "shape", "frame": {"x": 1500, "y": 700, "width": 300, "height": 200},
         "kind": "roundedRectangle", "fill": "#FFFFFF", "cornerRadius": 50},
        {"id": "e8", "type": "shape", "frame": {"x": 0, "y": 0, "width": 200, "height": 100}, "kind": "arrow"},
        {"id": "e9", "type": "shape", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, "kind": "star",
         "stroke": {"dash": [4, 2]}},
        {"id": "e10", "type": "shape", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, "kind": "triangle",
         "fill": "#00FF00"},
        {"id": "e11", "type": "shape", "frame": {"x": 0, "y": 0, "width": 100, "height": 100, "rotation": -90},
         "kind": "rectangle"},
        {"id": "e12", "type": "shape", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, "kind": "hexagon"},
        {"id": "e13", "type": "diagram", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, "paragraphs": 7},
        {"id": "e7", "type": "image", "frame": {"x": 1500, "y": 100, "width": 200, "height": 100},
         "source": "asset:logo-1", "altText": "Our logo"}
      ],
      "notes": "Welcome everyone.\n\nSecond line"
    },
    {
      "id": "s2",
      "background": {"image": "photos/sky.png"},
      "elements": [
        {"id": "e3", "type": "image", "frame": {"x": 0, "y": 0, "width": 960, "height": 1080},
         "source": "photos/dog.png", "altText": "A dog on a beach", "fit": "cover"},
        {"id": "e3b", "type": "image", "frame": {"x": 0, "y": 0, "width": 400, "height": 400},
         "source": "photos/dog.png"},
        {"id": "e4", "type": "line", "frame": {"x": 1000, "y": 200, "width": 600, "height": 0},
         "stroke": {"color": "#FF0000", "width": 3, "dash": "dot"}, "flipped": true, "endCap": "arrow", "opacity": 0.5},
        {"id": "g1", "type": "group", "frame": {"x": 200, "y": 300, "width": 400, "height": 200, "rotation": 30},
         "children": [
           {"id": "c1", "type": "shape", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, "kind": "rectangle"},
           {"id": "g2", "type": "group", "frame": {"x": 200, "y": 0, "width": 200, "height": 200},
            "children": [{"id": "c2", "type": "line", "frame": {"x": 0, "y": 0, "width": 200, "height": 200},
                          "startCap": "arrow"}]}
         ]}
      ]
    },
    {"id": "s3", "elements": []}
  ]
}`

// pngBytes is a w by h PNG.
func pngBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewRGBA(image.Rect(0, 0, w, h))); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

// fakeImages opens pictures from a map, and counts how often each is opened.
type fakeImages struct {
	files  map[string][]byte
	opened map[string]int
}

func (f *fakeImages) open(source string) (io.ReadCloser, int64, error) {
	if f.opened == nil {
		f.opened = map[string]int{}
	}
	f.opened[source]++
	body, ok := f.files[source]
	if !ok {
		return nil, 0, os.ErrNotExist
	}
	return io.NopCloser(bytes.NewReader(body)), int64(len(body)), nil
}

// pptx is an exported package, its parts by name.
type pptx map[string]string

func export(t *testing.T, deck string, images *fakeImages) (pptx, pptxutil.ExportQslideResult) {
	t.Helper()
	var out bytes.Buffer
	params := pptxutil.ExportQslideParams{Source: strings.NewReader(deck), Out: &out}
	if images != nil {
		params.OpenImage = images.open
	}
	result, err := pptxutil.ExportQslide(params)
	if err != nil {
		t.Fatalf("ExportQslide: %v", err)
	}
	return unzip(t, out.Bytes()), result
}

func unzip(t *testing.T, body []byte) pptx {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatalf("not a zip: %v", err)
	}
	parts := pptx{}
	for _, f := range zr.File {
		if _, dup := parts[f.Name]; dup {
			t.Errorf("part %s written twice", f.Name)
		}
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		b, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			t.Fatal(err)
		}
		parts[f.Name] = string(b)
	}
	return parts
}

func (p pptx) part(t *testing.T, name string) string {
	t.Helper()
	body, ok := p[name]
	if !ok {
		t.Fatalf("no part %s", name)
	}
	return body
}

// contains fails for each of want that body lacks.
func contains(t *testing.T, what, body string, want ...string) {
	t.Helper()
	for _, w := range want {
		if !strings.Contains(body, w) {
			t.Errorf("%s lacks %s", what, w)
		}
	}
}

func lacks(t *testing.T, what, body string, unwanted ...string) {
	t.Helper()
	for _, w := range unwanted {
		if strings.Contains(body, w) {
			t.Errorf("%s has %s", what, w)
		}
	}
}

func TestExportWritesACompleteWellFormedPackage(t *testing.T) {
	images := &fakeImages{files: map[string][]byte{
		"photos/dog.png": pngBytes(t, 400, 200),
		"photos/sky.png": pngBytes(t, 10, 10),
	}}
	parts, result := export(t, sampleDeck, images)
	if result.Slides != 3 || result.Pictures != 2 || result.MissingPictures != 1 {
		t.Errorf("result = %+v", result)
	}

	for _, name := range []string{
		"[Content_Types].xml", "_rels/.rels", "docProps/core.xml", "docProps/app.xml",
		"ppt/presentation.xml", "ppt/_rels/presentation.xml.rels",
		"ppt/slideMasters/slideMaster1.xml", "ppt/slideLayouts/slideLayout1.xml", "ppt/theme/theme1.xml",
		"ppt/notesMasters/notesMaster1.xml", "ppt/theme/theme2.xml",
		"ppt/slides/slide1.xml", "ppt/slides/slide2.xml", "ppt/slides/slide3.xml",
		"ppt/notesSlides/notesSlide1.xml", "ppt/media/image1.png", "ppt/media/image2.png",
	} {
		parts.part(t, name)
	}
	if _, ok := parts["ppt/notesSlides/notesSlide2.xml"]; ok {
		t.Error("a slide without notes has a notes slide")
	}

	types := parts.part(t, "[Content_Types].xml")
	for name, body := range parts {
		ext := path.Ext(name)
		if ext == ".xml" || ext == ".rels" {
			wellFormed(t, name, body)
		}
		// Every part has a content type, by override or by extension.
		if !strings.Contains(types, `PartName="/`+name+`"`) &&
			!strings.Contains(types, `Extension="`+strings.TrimPrefix(ext, ".")+`"`) {
			t.Errorf("%s has no content type", name)
		}
		// Every relationship points at a part in the package.
		if ext == ".rels" {
			dir := path.Dir(path.Dir(name))
			for _, target := range relTargets(t, body) {
				resolved := path.Join(dir, target)
				if dir == "." {
					resolved = target
				}
				if _, ok := parts[resolved]; !ok {
					t.Errorf("%s points at missing %s", name, resolved)
				}
			}
		}
	}
	// Every slide part has relationships.
	for i := 1; i <= 3; i++ {
		parts.part(t, fmt.Sprintf("ppt/slides/_rels/slide%d.xml.rels", i))
	}
	contains(t, "core", parts["docProps/core.xml"], "<dc:title>Sample &amp; deck</dc:title>")
	contains(t, "app", parts["docProps/app.xml"], "<Slides>3</Slides>", "<Notes>1</Notes>")
}

// wellFormed fails unless body parses as XML to the end.
func wellFormed(t *testing.T, name, body string) {
	t.Helper()
	dec := xml.NewDecoder(strings.NewReader(body))
	for {
		_, err := dec.Token()
		if errors.Is(err, io.EOF) {
			return
		}
		if err != nil {
			t.Errorf("%s is not well-formed: %v", name, err)
			return
		}
	}
}

// relTargets are the Target attributes of a relationships part.
func relTargets(t *testing.T, body string) []string {
	t.Helper()
	var rels struct {
		Relationship []struct {
			Target string `xml:"Target,attr"`
		}
	}
	if err := xml.Unmarshal([]byte(body), &rels); err != nil {
		t.Fatal(err)
	}
	var targets []string
	for _, r := range rels.Relationship {
		targets = append(targets, r.Target)
	}
	return targets
}

func TestExportScalesTheSlideSizeToEMU(t *testing.T) {
	for _, tc := range []struct {
		width, height float64
		want          string
	}{
		{1920, 1080, `<p:sldSz cx="12192000" cy="6858000"/>`},
		{1024, 768, `<p:sldSz cx="12192000" cy="9144000"/>`},
		// Too short to scale by width: the height takes PowerPoint's minimum.
		{1920, 10, `<p:sldSz cx="51206400" cy="914400"/>`},
	} {
		deck := fmt.Sprintf(`{"schemaVersion":1,"size":{"width":%g,"height":%g},"slides":[]}`, tc.width, tc.height)
		parts, _ := export(t, deck, nil)
		contains(t, fmt.Sprintf("%gx%g", tc.width, tc.height), parts.part(t, "ppt/presentation.xml"), tc.want)
	}
}

func TestExportDrawsShapesWithTheirFillOutlineAndRotation(t *testing.T) {
	parts, _ := export(t, sampleDeck, nil)
	slide := parts.part(t, "ppt/slides/slide1.xml")
	contains(t, "slide 1", slide,
		// The background color.
		`<p:bg><p:bgPr><a:solidFill><a:srgbClr val="102030"/></a:solidFill>`,
		// The ellipse: half a point per unit, rotated 15°, its fill's own
		// alpha (0x80) times the shape's opacity, its outline too.
		`<a:xfrm rot="900000"><a:off x="638175" y="3810000"/><a:ext cx="2540000" cy="1905000"/></a:xfrm>`,
		`<a:prstGeom prst="ellipse">`,
		`<a:srgbClr val="3366FF"><a:alpha val="37647"/></a:srgbClr>`,
		`<a:ln w="25400"><a:solidFill><a:srgbClr val="FFFFFF"><a:alpha val="75000"/></a:srgbClr></a:solidFill><a:prstDash val="dashDot"/></a:ln>`,
		// A 50-unit radius on a 200-unit side.
		`<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 25000"/></a:avLst>`,
		`<a:prstGeom prst="rightArrow"><a:avLst><a:gd name="adj1" fmla="val 40000"/><a:gd name="adj2" fmla="val 80000"/></a:avLst>`,
		`<a:prstGeom prst="star5"><a:avLst><a:gd name="adj" fmla="val 20000"/></a:avLst>`,
		`<a:prstGeom prst="triangle">`,
		`<a:srgbClr val="00FF00"/>`,
		// A quarter turn back is three quarters forward.
		`<a:xfrm rot="16200000">`,
		// No stroke is no outline, and no fill is none.
		`<a:noFill/><a:ln><a:noFill/></a:ln>`,
	)
	// A dash written as an array draws solid; an unknown kind and an unknown
	// type are left out.
	lacks(t, "slide 1", slide, `prstDash val="[`, "hexagon", "diagram")
	if got := strings.Count(slide, "<p:sp>"); got != 8 {
		t.Errorf("slide 1 has %d shapes, want 8 (6 shapes, a text box, a placeholder)", got)
	}
}

func TestExportWritesRichText(t *testing.T) {
	parts, _ := export(t, sampleDeck, nil)
	slide := parts.part(t, "ppt/slides/slide1.xml")
	contains(t, "slide 1", slide,
		`<p:cNvSpPr txBox="1"/>`,
		`<a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr" rtlCol="0"><a:normAutofit/></a:bodyPr>`,
		`<a:pPr algn="ctr"><a:buNone/></a:pPr>`,
		`<a:r><a:rPr lang="en-US" sz="3600" dirty="0"></a:rPr><a:t>Hello, </a:t></a:r>`,
		`<a:rPr lang="en-US" sz="3600" b="1" i="1" u="sng" strike="sngStrike" dirty="0">`+
			`<a:solidFill><a:srgbClr val="FFCC00"/></a:solidFill><a:latin typeface="Inter"/><a:cs typeface="Inter"/></a:rPr>`+
			`<a:t>slides</a:t>`,
		// The blank line keeps the default size.
		`<a:p><a:pPr algn="l"><a:buNone/></a:pPr><a:endParaRPr lang="en-US" sz="1800" dirty="0"></a:endParaRPr></a:p>`,
		// 1.5 lines against PowerPoint's 1.2 single spacing; numbered.
		`<a:lnSpc><a:spcPct val="125000"/></a:lnSpc><a:buFont typeface="+mj-lt"/><a:buAutoNum type="arabicPeriod"/>`,
		`<a:t>Second &lt;line&gt;</a:t>`,
		// A 36-unit run's marker gutter is 54 units.
		`<a:pPr marL="342900" indent="-342900" algn="r"><a:buFont typeface="Arial"/><a:buChar char="•"/></a:pPr>`,
		`<a:latin typeface="Times New Roman"/>`,
	)
	lacks(t, "slide 1", slide, "Click to add title")
}

func TestExportWritesLinesAndArrows(t *testing.T) {
	parts, _ := export(t, sampleDeck, nil)
	slide := parts.part(t, "ppt/slides/slide2.xml")
	contains(t, "slide 2", slide,
		`<p:cxnSp>`,
		`<a:xfrm flipV="1"><a:off x="6350000" y="1270000"/><a:ext cx="3810000" cy="0"/></a:xfrm><a:prstGeom prst="line">`,
		`<a:ln w="19050" cap="rnd"><a:solidFill><a:srgbClr val="FF0000"><a:alpha val="50000"/></a:srgbClr></a:solidFill>`+
			`<a:prstDash val="sysDot"/><a:tailEnd type="triangle" w="med" len="med"/></a:ln>`,
		`<a:headEnd type="triangle" w="med" len="med"/></a:ln>`,
	)
}

func TestExportWritesGroupsInGroupLocalSpace(t *testing.T) {
	parts, _ := export(t, sampleDeck, nil)
	slide := parts.part(t, "ppt/slides/slide2.xml")
	contains(t, "slide 2", slide,
		`<p:grpSpPr><a:xfrm rot="1800000"><a:off x="1270000" y="1905000"/><a:ext cx="2540000" cy="1270000"/>`+
			`<a:chOff x="0" y="0"/><a:chExt cx="2540000" cy="1270000"/></a:xfrm></p:grpSpPr>`,
		// The nested group sits 200 units into its parent.
		`<a:xfrm><a:off x="1270000" y="0"/><a:ext cx="1270000" cy="1270000"/><a:chOff x="0" y="0"/>`,
	)
	if got := strings.Count(slide, "<p:grpSp>"); got != 2 {
		t.Errorf("slide 2 has %d groups, want 2", got)
	}
	if !strings.Contains(slide, "</p:grpSp></p:grpSp>") {
		t.Error("the inner group is not nested in the outer one")
	}
}

func TestExportEmbedsPicturesOnceAndFitsThem(t *testing.T) {
	images := &fakeImages{files: map[string][]byte{
		"photos/dog.png": pngBytes(t, 400, 200),
		"photos/sky.png": pngBytes(t, 10, 10),
	}}
	parts, _ := export(t, sampleDeck, images)
	if images.opened["photos/dog.png"] != 1 {
		t.Errorf("dog.png opened %d times, want once", images.opened["photos/dog.png"])
	}
	if parts["ppt/media/image1.png"] != string(images.files["photos/sky.png"]) {
		t.Error("the background picture is not embedded byte for byte")
	}
	if parts["ppt/media/image2.png"] != string(images.files["photos/dog.png"]) {
		t.Error("the picture is not embedded byte for byte")
	}

	slide := parts.part(t, "ppt/slides/slide2.xml")
	rels := parts.part(t, "ppt/slides/_rels/slide2.xml.rels")
	contains(t, "slide 2 rels", rels, `Target="../media/image1.png"`, `Target="../media/image2.png"`)
	if strings.Count(rels, "image2.png") != 1 {
		t.Error("a picture shown twice is related twice")
	}
	contains(t, "slide 2", slide,
		// The background covers the slide, behind everything.
		`descr="Background"/>`,
		`<p:pic><p:nvPicPr><p:cNvPr id="3" name="Picture 3" descr="A dog on a beach"/>`,
		// A 2:1 picture covering a 960×1080 frame loses the sides.
		`<a:blip r:embed="rId3"/><a:srcRect l="27778" r="27778"/><a:stretch><a:fillRect/></a:stretch>`,
		// Contained in a square, it is a centered 400×200 box.
		`<a:xfrm><a:off x="0" y="635000"/><a:ext cx="2540000" cy="1270000"/></a:xfrm>`,
	)
	if !strings.HasPrefix(strings.SplitN(slide, "<p:pic>", 2)[1], "<p:nvPicPr><p:cNvPr id=\"2\" name=\"Picture 2\" descr=\"Background\"/>") {
		t.Error("the background picture is not first in the shape tree")
	}
	// LibreOffice refuses a stored entry written with a data descriptor,
	// which is how a streamed entry has to be stored, so media is deflated.
	var out bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(sampleDeck), Out: &out, OpenImage: images.open,
	}); err != nil {
		t.Fatal(err)
	}
	zr, _ := zip.NewReader(bytes.NewReader(out.Bytes()), int64(out.Len()))
	for _, f := range zr.File {
		if strings.HasPrefix(f.Name, "ppt/media/") && f.Method != zip.Deflate {
			t.Errorf("%s is written with method %d, want deflate", f.Name, f.Method)
		}
	}
	contains(t, "content types", parts.part(t, "[Content_Types].xml"), `<Default Extension="png" ContentType="image/png"/>`)
}

func TestExportDrawsAPlaceholderForAPictureItCannotEmbed(t *testing.T) {
	deck := `{"schemaVersion":1,"slides":[{"id":"s1","elements":[
		{"id":"a","type":"image","frame":{"x":0,"y":0,"width":100,"height":50},"source":"missing.png","altText":"Gone"},
		{"id":"b","type":"image","frame":{"x":0,"y":0,"width":100,"height":50},"source":"notes.txt"}
	]}]}`
	images := &fakeImages{files: map[string][]byte{"notes.txt": []byte("not a picture")}}
	parts, result := export(t, deck, images)
	if result.Pictures != 0 || result.MissingPictures != 2 {
		t.Errorf("result = %+v", result)
	}
	slide := parts.part(t, "ppt/slides/slide1.xml")
	contains(t, "slide", slide, `name="Picture 2" descr="Gone"/>`, `<a:srgbClr val="D9D9D9"/>`)
	lacks(t, "slide", slide, "<p:pic>")
	for name := range parts {
		if strings.HasPrefix(name, "ppt/media/") {
			t.Errorf("unexpected media %s", name)
		}
	}
}

func TestExportWritesSpeakerNotes(t *testing.T) {
	parts, _ := export(t, sampleDeck, nil)
	notes := parts.part(t, "ppt/notesSlides/notesSlide1.xml")
	contains(t, "notes", notes,
		`<p:ph type="body" idx="1"/>`,
		`<a:t>Welcome everyone.</a:t>`,
		`<a:p><a:endParaRPr lang="en-US"/></a:p>`,
		`<a:t>Second line</a:t>`,
	)
	contains(t, "slide 1 rels", parts.part(t, "ppt/slides/_rels/slide1.xml.rels"),
		`Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide1.xml"`)
	contains(t, "notes rels", parts.part(t, "ppt/notesSlides/_rels/notesSlide1.xml.rels"), `Target="../slides/slide1.xml"`)
}

func TestExportPlacesSlidesReadBeforeTheSize(t *testing.T) {
	deck := `{"slides":[{"id":"s1","elements":[
		{"id":"a","type":"shape","kind":"rectangle","frame":{"x":1024,"y":0,"width":10,"height":10}}]}],
		"size":{"width":1024,"height":768},"schemaVersion":1}`
	parts, _ := export(t, deck, nil)
	// 1024 units is the full 12,192,000 EMU width, not the 16:9 default's.
	contains(t, "slide", parts.part(t, "ppt/slides/slide1.xml"), `<a:off x="12192000" y="0"/>`)
}

func TestExportRefusesWhatIsNotAQslide(t *testing.T) {
	for name, deck := range map[string]string{
		"empty":         ``,
		"not json":      `hello`,
		"no version":    `{"slides":[]}`,
		"newer version": `{"schemaVersion":6,"slides":[]}`,
		"bad size":      `{"schemaVersion":1,"size":{"width":0,"height":10},"slides":[]}`,
		"bad slide":     `{"schemaVersion":1,"slides":[{"elements":"no"}]}`,
	} {
		var out bytes.Buffer
		_, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{Source: strings.NewReader(deck), Out: &out})
		if !errors.Is(err, pptxutil.ErrNotQslide) {
			t.Errorf("%s: err = %v, want ErrNotQslide", name, err)
		}
		if out.Len() != 0 {
			t.Errorf("%s: wrote %d bytes before failing", name, out.Len())
		}
	}
}

func TestExportRefusesGroupsNestedTooDeep(t *testing.T) {
	group := `{"id":"x","type":"shape","kind":"rectangle","frame":{"x":0,"y":0,"width":1,"height":1}}`
	for range pptxutil.MaxGroupDepth + 1 {
		group = `{"id":"g","type":"group","frame":{"x":0,"y":0,"width":1,"height":1},"children":[` + group + `]}`
	}
	deck := `{"schemaVersion":1,"slides":[{"id":"s1","elements":[` + group + `]}]}`
	_, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{Source: strings.NewReader(deck), Out: io.Discard})
	if !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("err = %v, want ErrTooLarge", err)
	}
}

func TestExportRefusesASourcePastTheCap(t *testing.T) {
	deck := io.MultiReader(strings.NewReader(`{"schemaVersion":1,"title":"`),
		strings.NewReader(strings.Repeat("a", pptxutil.MaxQslideBytes)), strings.NewReader(`"}`))
	_, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{Source: deck, Out: io.Discard})
	if !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("err = %v, want ErrTooLarge", err)
	}
}
