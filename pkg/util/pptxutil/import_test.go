package pptxutil_test

// cspell:ignore autofit clr descr dgm ffcc lum ph prst srgb sslide xfrm

import (
	"archive/zip"
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"reflect"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// roundTripDeck uses every feature an import reads back exactly. Every run
// sets its size, font and color, since an import writes out what a run
// inherits; pictures are named as the export names them, so the references
// an import stores them under are the ones the deck started with.
const roundTripDeck = `{
  "schemaVersion": 1,
  "title": "Round & trip",
  "size": {"width": 1920, "height": 1080},
  "slides": [
    {
      "id": "s1",
      "background": {"color": "#102030"},
      "elements": [
        {"id": "e1", "type": "text", "frame": {"x": 160, "y": 120, "width": 1600, "height": 240},
         "paragraphs": [
           {"runs": [{"text": "Hello, ", "fontSize": 72, "fontFamily": "Inter", "color": "#000000"},
                     {"text": "slides", "bold": true, "italic": true, "underline": true, "strikethrough": true,
                      "fontSize": 72, "fontFamily": "Inter", "color": "#FFCC00"}],
            "align": "center"},
           {"runs": []},
           {"runs": [{"text": "Second <line>", "fontSize": 36, "fontFamily": "Inter", "color": "#000000"}],
            "lineSpacing": 1.5, "list": "numbered"},
           {"runs": [{"text": "A bullet", "fontSize": 40, "fontFamily": "Georgia", "color": "#33333380"}],
            "align": "end", "list": "bullet"},
           {"runs": [{"text": "Justified", "fontSize": 36, "fontFamily": "Inter", "color": "#000000"}],
            "align": "justify"}
         ],
         "anchor": "middle", "autoFit": "shrink"},
        {"id": "e1b", "type": "text", "frame": {"x": 0, "y": 900, "width": 300, "height": 100},
         "paragraphs": [{"runs": [{"text": "Grows", "fontSize": 36, "fontFamily": "Inter", "color": "#000000"}]}],
         "anchor": "bottom"},
        {"id": "e2", "type": "shape", "frame": {"x": 100.5, "y": 600, "width": 400, "height": 300, "rotation": 15},
         "kind": "ellipse", "fill": "#3366FF80", "stroke": {"color": "#FFFFFF", "width": 4, "dash": "dashDot"}},
        {"id": "e3", "type": "shape", "frame": {"x": 1500, "y": 700, "width": 300, "height": 200},
         "kind": "roundedRectangle", "fill": "#FFFFFF", "cornerRadius": 50},
        {"id": "e4", "type": "shape", "frame": {"x": 10, "y": 10, "width": 200, "height": 100}, "kind": "arrow",
         "fill": "#00FF00"},
        {"id": "e5", "type": "shape", "frame": {"x": 20, "y": 20, "width": 100, "height": 100}, "kind": "star",
         "stroke": {"color": "#000000", "width": 2, "dash": "dash"}},
        {"id": "e6", "type": "shape", "frame": {"x": 30, "y": 30, "width": 100, "height": 100}, "kind": "triangle",
         "fill": "#00FF00"},
        {"id": "e7", "type": "shape", "frame": {"x": 40, "y": 40, "width": 100, "height": 100}, "kind": "diamond",
         "fill": "#ABCDEF"},
        {"id": "e8", "type": "shape", "frame": {"x": 50, "y": 50, "width": 100, "height": 100, "rotation": 270},
         "kind": "rectangle"},
        {"id": "e9", "type": "image", "frame": {"x": 1500, "y": 100, "width": 200, "height": 100},
         "source": "pics/image1.png", "altText": "Our logo", "fit": "fill"}
      ],
      "notes": "Welcome everyone.\n\nSecond line"
    },
    {
      "id": "s2",
      "elements": [
        {"id": "e10", "type": "image", "frame": {"x": 0, "y": 0, "width": 960, "height": 1080},
         "source": "pics/image2.png", "altText": "A dog on a beach", "fit": "cover"},
        {"id": "e11", "type": "image", "frame": {"x": 1000, "y": 500, "width": 200, "height": 100},
         "source": "pics/image1.png", "fit": "fill"},
        {"id": "e12", "type": "line", "frame": {"x": 1000, "y": 200, "width": 600, "height": 0},
         "stroke": {"color": "#FF0000", "width": 3, "dash": "dot"}, "flipped": true, "endCap": "arrow"},
        {"id": "g1", "type": "group", "frame": {"x": 200, "y": 300, "width": 400, "height": 200, "rotation": 30},
         "children": [
           {"id": "c1", "type": "shape", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, "kind": "rectangle",
            "fill": "#00FF00"},
           {"id": "g2", "type": "group", "frame": {"x": 200, "y": 0, "width": 200, "height": 200},
            "children": [{"id": "c2", "type": "line", "frame": {"x": 0, "y": 0, "width": 200, "height": 200},
                          "stroke": {"color": "#000000", "width": 2}, "startCap": "arrow"}]}
         ]}
      ]
    },
    {"id": "s3", "elements": []}
  ]
}`

// mediaStore stores pictures in memory, under pics/<name>.
type mediaStore struct {
	files map[string][]byte
	// fail, when set, fails every store.
	fail error
}

func (m *mediaStore) store(name string, r io.Reader) (string, error) {
	if m.fail != nil {
		return "", m.fail
	}
	body, err := io.ReadAll(r)
	if err != nil {
		return "", err
	}
	if m.files == nil {
		m.files = map[string][]byte{}
	}
	ref := "pics/" + name
	m.files[ref] = body
	return ref, nil
}

// importPptx imports body and returns the .qslide decoded, and the result.
func importPptx(t *testing.T, body []byte, media *mediaStore) (map[string]any, pptxutil.ImportPptxResult) {
	t.Helper()
	var out bytes.Buffer
	params := pptxutil.ImportPptxParams{Source: bytes.NewReader(body), Size: int64(len(body)), Out: &out, Title: "Fallback"}
	if media != nil {
		params.StoreMedia = media.store
	}
	result, err := pptxutil.ImportPptx(params)
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	var doc map[string]any
	if err := json.Unmarshal(out.Bytes(), &doc); err != nil {
		t.Fatalf("the import is not JSON: %v\n%s", err, out.String())
	}
	return doc, result
}

// withoutIDs drops every "id", which an import numbers afresh.
func withoutIDs(v any) any {
	switch v := v.(type) {
	case map[string]any:
		out := map[string]any{}
		for k, val := range v {
			if k != "id" {
				out[k] = withoutIDs(val)
			}
		}
		return out
	case []any:
		out := make([]any, len(v))
		for i, val := range v {
			out[i] = withoutIDs(val)
		}
		return out
	}
	return v
}

func TestImportReadsBackWhatTheExportWrote(t *testing.T) {
	images := &fakeImages{files: map[string][]byte{
		"pics/image1.png": pngBytes(t, 200, 100),
		"pics/image2.png": pngBytes(t, 100, 100),
	}}
	var exported bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(roundTripDeck), Out: &exported, OpenImage: images.open,
	}); err != nil {
		t.Fatal(err)
	}

	media := &mediaStore{}
	got, result := importPptx(t, exported.Bytes(), media)
	var want map[string]any
	if err := json.Unmarshal([]byte(roundTripDeck), &want); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(withoutIDs(got), withoutIDs(want)) {
		gotJSON, _ := json.MarshalIndent(withoutIDs(got), "", "  ")
		t.Errorf("round trip changed the deck:\n%s", gotJSON)
	}
	if result.Slides != 3 || result.Pictures != 2 || len(result.Warnings) != 0 {
		t.Errorf("result = %+v, want 3 slides, 2 pictures and no warnings", result)
	}
	// Each picture is stored once, byte for byte.
	if len(media.files) != 2 || !bytes.Equal(media.files["pics/image2.png"], images.files["pics/image2.png"]) {
		t.Errorf("stored media = %d files", len(media.files))
	}
}

func TestImportGivesEverySlideAndElementAUniqueID(t *testing.T) {
	var exported bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(roundTripDeck), Out: &exported,
	}); err != nil {
		t.Fatal(err)
	}
	doc, _ := importPptx(t, exported.Bytes(), nil)
	seen := map[string]bool{}
	var walk func(v any)
	walk = func(v any) {
		switch v := v.(type) {
		case map[string]any:
			if id, ok := v["id"].(string); ok {
				if seen[id] {
					t.Errorf("id %q is used twice", id)
				}
				seen[id] = true
			}
			for _, val := range v {
				walk(val)
			}
		case []any:
			for _, val := range v {
				walk(val)
			}
		}
	}
	walk(doc)
	if len(seen) < 15 {
		t.Errorf("only %d ids", len(seen))
	}
}

// pptxBuilder assembles a package from hand-written parts, for the features
// this package's own export never writes.
type pptxBuilder map[string]string

// ns declares the PresentationML namespaces a hand-written part uses.
const ns = `xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ` +
	`xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ` +
	`xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"`

const relNS = `http://schemas.openxmlformats.org/officeDocument/2006/relationships/`

// rels is a relationships part; each entry is id, type, target.
func rels(entries ...[3]string) string {
	var b strings.Builder
	b.WriteString(`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`)
	for _, e := range entries {
		fmt.Fprintf(&b, `<Relationship Id="%s" Type="%s%s" Target="%s"/>`, e[0], relNS, e[1], e[2])
	}
	b.WriteString(`</Relationships>`)
	return b.String()
}

// deck is a package whose master has a title and body placeholder and a
// theme, with the given slides, each using the one layout.
func deck(slides ...string) pptxBuilder {
	b := pptxBuilder{
		"_rels/.rels": rels([3]string{"rId1", "officeDocument", "ppt/presentation.xml"}),
		"ppt/theme/theme1.xml": `<a:theme ` + ns + ` name="T"><a:themeElements><a:clrScheme name="T">` +
			`<a:dk1><a:sysClr val="windowText" lastClr="1F1F1F"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>` +
			`<a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>` +
			`<a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2>` +
			`</a:clrScheme><a:fontScheme name="T"><a:majorFont><a:latin typeface="Calibri Light"/></a:majorFont>` +
			`<a:minorFont><a:latin typeface="Calibri"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>`,
		"ppt/slideMasters/slideMaster1.xml": `<p:sldMaster ` + ns + `><p:cSld>` +
			`<p:bg><p:bgPr><a:solidFill><a:schemeClr val="bg2"/></a:solidFill></p:bgPr></p:bg><p:spTree>` +
			`<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>` +
			`<p:spPr><a:xfrm><a:off x="838200" y="365125"/><a:ext cx="10515600" cy="1325563"/></a:xfrm></p:spPr>` +
			`<p:txBody><a:bodyPr anchor="ctr"/><a:p><a:r><a:t>Title prompt</a:t></a:r></a:p></p:txBody></p:sp>` +
			`<p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>` +
			`<p:spPr><a:xfrm><a:off x="838200" y="1825625"/><a:ext cx="10515600" cy="4351338"/></a:xfrm></p:spPr>` +
			`<p:txBody><a:bodyPr/><a:p><a:r><a:t>Body prompt</a:t></a:r></a:p></p:txBody></p:sp>` +
			`<p:sp><p:nvSpPr><p:cNvPr id="4" name="Logo"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>` +
			`<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="635000" cy="635000"/></a:xfrm>` +
			`<a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val="accent2"/></a:solidFill></p:spPr></p:sp>` +
			`</p:spTree></p:cSld>` +
			`<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2"/>` +
			`<p:txStyles><p:titleStyle><a:lvl1pPr algn="ctr"><a:buNone/><a:defRPr sz="4400" b="1">` +
			`<a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mj-lt"/></a:defRPr></a:lvl1pPr></p:titleStyle>` +
			`<p:bodyStyle><a:lvl1pPr><a:buChar char="•"/><a:defRPr sz="2800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>` +
			`<a:latin typeface="+mn-lt"/></a:defRPr></a:lvl1pPr><a:lvl2pPr><a:buChar char="-"/><a:defRPr sz="2400"/></a:lvl2pPr>` +
			`</p:bodyStyle></p:txStyles></p:sldMaster>`,
		"ppt/slideMasters/_rels/slideMaster1.xml.rels": rels([3]string{"rId1", "theme", "../theme/theme1.xml"}),
		"ppt/slideLayouts/slideLayout1.xml": `<p:sldLayout ` + ns + `><p:cSld><p:spTree>` +
			`<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr>` +
			`<p:spPr/></p:sp></p:spTree></p:cSld></p:sldLayout>`,
		"ppt/slideLayouts/_rels/slideLayout1.xml.rels": rels([3]string{"rId1", "slideMaster", "../slideMasters/slideMaster1.xml"}),
	}
	var ids, presRels strings.Builder
	presRels.WriteString(`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">`)
	for i, slide := range slides {
		n := i + 1
		fmt.Fprintf(&ids, `<p:sldId id="%d" r:id="rId%d"/>`, 255+n, 10+n)
		fmt.Fprintf(&presRels, `<Relationship Id="rId%d" Type="%sslide" Target="slides/slide%d.xml"/>`, 10+n, relNS, n)
		b[fmt.Sprintf("ppt/slides/slide%d.xml", n)] = `<p:sld ` + ns + `><p:cSld><p:spTree>` + slide + `</p:spTree></p:cSld></p:sld>`
		if _, ok := b[fmt.Sprintf("ppt/slides/_rels/slide%d.xml.rels", n)]; !ok {
			b[fmt.Sprintf("ppt/slides/_rels/slide%d.xml.rels", n)] = rels(
				[3]string{"rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"},
				[3]string{"rId2", "image", "../media/image1.png"},
				[3]string{"rId3", "image", "../media/image2.emf"},
			)
		}
	}
	presRels.WriteString(`</Relationships>`)
	b["ppt/presentation.xml"] = `<p:presentation ` + ns + `><p:sldIdLst>` + ids.String() +
		`</p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>`
	b["ppt/_rels/presentation.xml.rels"] = presRels.String()
	return b
}

func (b pptxBuilder) zip(t *testing.T) []byte {
	t.Helper()
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for name, body := range b {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return out.Bytes()
}

// slides is the decoded deck's slides.
func slides(doc map[string]any) []map[string]any {
	var out []map[string]any
	for _, s := range doc["slides"].([]any) {
		out = append(out, s.(map[string]any))
	}
	return out
}

// elements is a slide's elements.
func elements(slide map[string]any) []map[string]any {
	var out []map[string]any
	for _, e := range slide["elements"].([]any) {
		out = append(out, e.(map[string]any))
	}
	return out
}

// asJSON is v compact, for comparing a fragment.
func asJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

func TestImportFillsPlaceholdersFromTheirLayoutMasterAndTheme(t *testing.T) {
	b := deck(
		`<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title 1"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>` +
			`<p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr><p:spPr/>` +
			`<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/><a:t>Quarterly review</a:t></a:r></a:p></p:txBody></p:sp>` +
			`<p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr/><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>` +
			`<p:txBody><a:bodyPr/><a:p><a:r><a:t>First point</a:t></a:r></a:p>` +
			`<a:p><a:pPr lvl="1"/><a:r><a:t>Detail</a:t></a:r></a:p></p:txBody></p:sp>` +
			`<p:sp><p:nvSpPr><p:cNvPr id="4" name="Empty"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="2"/></p:nvPr></p:nvSpPr>` +
			`<p:spPr/><p:txBody><a:bodyPr/><a:p><a:endParaRPr/></a:p></p:txBody></p:sp>`,
	)
	doc, result := importPptx(t, b.zip(t), &mediaStore{})
	if len(result.Warnings) != 0 {
		t.Errorf("warnings = %v", result.Warnings)
	}
	slide := slides(doc)[0]
	els := elements(slide)
	// The master's own ellipse, in its theme color, then the title and body;
	// the empty placeholder is a prompt and is left out.
	if len(els) != 3 {
		t.Fatalf("elements = %s", asJSON(els))
	}
	if got := asJSON(els[0]["fill"]); got != `"#ED7D31"` || els[0]["kind"] != "ellipse" {
		t.Errorf("master shape = %s", asJSON(els[0]))
	}
	title := els[1]
	// The master's title box, inset by the default 0.1 in by 0.05 in.
	if got, want := asJSON(title["frame"]), `{"height":194.35,"width":1627.2,"x":146.4,"y":64.7}`; got != want {
		t.Errorf("title frame = %s, want %s", got, want)
	}
	if got, want := asJSON(title["paragraphs"]),
		`[{"align":"center","runs":[{"bold":true,"color":"#1F1F1F","fontFamily":"Calibri Light","fontSize":88,"text":"Quarterly review"}]}]`; got != want {
		t.Errorf("title paragraphs = %s, want %s", got, want)
	}
	if title["anchor"] != "middle" {
		t.Errorf("title anchor = %v, want the master's middle", title["anchor"])
	}
	if got, want := asJSON(els[2]["paragraphs"]),
		`[{"list":"bullet","runs":[{"color":"#1F1F1F","fontFamily":"Calibri","fontSize":56,"text":"First point"}]},`+
			`{"list":"bullet","runs":[{"fontSize":48,"text":"Detail"}]}]`; got != want {
		t.Errorf("body paragraphs = %s, want %s", got, want)
	}
	// The master's background is the theme's second light color.
	if got := asJSON(slide["background"]); got != `{"color":"#E7E6E6"}` {
		t.Errorf("background = %s", got)
	}
	if doc["title"] != "Fallback" {
		t.Errorf("title = %v, want the caller's fallback", doc["title"])
	}
}

func TestImportResolvesThemeColorsAndStyles(t *testing.T) {
	b := deck(
		// A PowerPoint-drawn shape: no fill or line of its own, its style's
		// instead, and its text in the style's font color.
		`<p:sp><p:nvSpPr><p:cNvPr id="2" name="Box"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>` +
			`<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="635000" cy="635000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>` +
			`<p:style><a:lnRef idx="2"><a:schemeClr val="accent1"><a:shade val="50000"/></a:schemeClr></a:lnRef>` +
			`<a:fillRef idx="1"><a:schemeClr val="accent1"/></a:fillRef><a:effectRef idx="0"><a:schemeClr val="accent1"/></a:effectRef>` +
			`<a:fontRef idx="minor"><a:schemeClr val="lt1"/></a:fontRef></p:style>` +
			`<p:txBody><a:bodyPr lIns="0" tIns="0" rIns="0" bIns="0"/><a:p><a:r><a:rPr sz="1200"/><a:t>Inside</a:t></a:r></a:p></p:txBody></p:sp>` +
			// Text 1, lighter 50%, at half alpha.
			`<p:sp><p:nvSpPr><p:cNvPr id="3" name="Tint"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>` +
			`<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="635000" cy="635000"/></a:xfrm><a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom>` +
			`<a:solidFill><a:schemeClr val="tx1"><a:lumMod val="50000"/><a:lumOff val="50000"/><a:alpha val="50000"/></a:schemeClr></a:solidFill>` +
			`<a:ln w="25400"><a:solidFill><a:prstClr val="red"/></a:solidFill><a:prstDash val="lgDash"/></a:ln></p:spPr></p:sp>`,
	)
	doc, _ := importPptx(t, b.zip(t), nil)
	els := elements(slides(doc)[0])[1:] // after the master's ellipse
	if len(els) != 3 {
		t.Fatalf("elements = %s", asJSON(els))
	}
	if got, want := asJSON(els[0]), `{"fill":"#4472C4","frame":{"height":100,"width":100,"x":0,"y":0},"id":"e2",`+
		`"kind":"rectangle","stroke":{"color":"#223962","width":2},"type":"shape"}`; got != want {
		t.Errorf("styled shape = %s, want %s", got, want)
	}
	if got, want := asJSON(els[1]["paragraphs"]),
		`[{"runs":[{"color":"#FFFFFF","fontSize":24,"text":"Inside"}]}]`; got != want {
		t.Errorf("text over the shape = %s, want %s", got, want)
	}
	if got, want := asJSON(els[2]["fill"]), `"#8F8F8F80"`; got != want {
		t.Errorf("tinted fill = %s, want %s", got, want)
	}
	if got, want := asJSON(els[2]["stroke"]), `{"color":"#FF0000","dash":"dash","width":4}`; got != want {
		t.Errorf("preset-colored stroke = %s, want %s", got, want)
	}
}

func TestImportSkipsWhatTheEditorCannotShowWithWarnings(t *testing.T) {
	frame := func(uri string) string {
		return `<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="9" name="F"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>` +
			`<p:xfrm><a:off x="0" y="0"/><a:ext cx="100" cy="100"/></p:xfrm>` +
			`<a:graphic><a:graphicData uri="` + uri + `"><x/></a:graphicData></a:graphic></p:graphicFrame>`
	}
	b := deck(
		frame("http://schemas.openxmlformats.org/drawingml/2006/table")+
			frame("http://schemas.openxmlformats.org/drawingml/2006/chart")+
			frame("http://schemas.openxmlformats.org/drawingml/2006/diagram")+
			frame("http://schemas.openxmlformats.org/presentationml/2006/ole")+
			`<p:sp><p:nvSpPr><p:cNvPr id="2" name="Hex"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>`+
			`<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="6350" cy="6350"/></a:xfrm><a:prstGeom prst="hexagon"><a:avLst/></a:prstGeom>`+
			`<a:gradFill><a:gsLst><a:gs pos="0"><a:srgbClr val="112233"/></a:gs><a:gs pos="100000"><a:srgbClr val="FFFFFF"/></a:gs></a:gsLst></a:gradFill></p:spPr></p:sp>`+
			`<p:pic><p:nvPicPr><p:cNvPr id="5" name="Movie"/><p:cNvPicPr/><p:nvPr><a:videoFile r:link="rId9"/></p:nvPr></p:nvPicPr>`+
			`<p:blipFill><a:blip r:embed="rId2"/></p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="6350" cy="6350"/></a:xfrm></p:spPr></p:pic>`+
			`<p:pic><p:nvPicPr><p:cNvPr id="6" name="Vector"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>`+
			`<p:blipFill><a:blip r:embed="rId3"/></p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="6350" cy="6350"/></a:xfrm></p:spPr></p:pic>`+
			`<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="7" name="Elbow"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>`+
			`<p:spPr><a:xfrm flipH="1"><a:off x="0" y="0"/><a:ext cx="6350" cy="6350"/></a:xfrm><a:prstGeom prst="bentConnector3"><a:avLst/></a:prstGeom>`+
			`<a:ln w="12700"><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:tailEnd type="arrow"/></a:ln></p:spPr></p:cxnSp>`+
			`<p:contentPart r:id="rId8"/>`,
		"",
	)
	b["ppt/slides/slide1.xml"] = strings.Replace(b["ppt/slides/slide1.xml"], `</p:cSld>`,
		`</p:cSld><p:timing><p:tnLst/></p:timing>`, 1)
	b["ppt/media/image1.png"] = string(pngBytes(t, 1, 1))
	b["ppt/media/image2.emf"] = "\x01\x00\x00\x00 not a picture the editor shows"

	doc, result := importPptx(t, b.zip(t), &mediaStore{})
	var messages []string
	for _, w := range result.Warnings {
		if w.Slide != 1 {
			t.Errorf("warning on slide %d: %s", w.Slide, w.Message)
		}
		messages = append(messages, w.Message)
	}
	want := []string{
		"Animations and transitions are not imported.",
		"Tables are not imported.",
		"Charts are not imported.",
		"SmartArt graphics are not imported.",
		"Embedded objects are not imported.",
		"Gradient fills were drawn in their first color.",
		"Shapes of a kind the editor does not have (hexagon) were drawn as rectangles.",
		"Video and audio are not imported.",
		"Pictures in a format the editor cannot show (EMF) were left out.",
		"Bent and curved connectors were drawn as straight lines.",
		"Ink drawings are not imported.",
	}
	if !reflect.DeepEqual(messages, want) {
		t.Errorf("warnings =\n%s\nwant\n%s", strings.Join(messages, "\n"), strings.Join(want, "\n"))
	}
	els := elements(slides(doc)[0])[1:]
	if len(els) != 2 {
		t.Fatalf("elements = %s", asJSON(els))
	}
	if els[0]["kind"] != "rectangle" || els[0]["fill"] != "#112233" {
		t.Errorf("unknown preset = %s", asJSON(els[0]))
	}
	if els[1]["type"] != "line" || els[1]["flipped"] != true || els[1]["endCap"] != "arrow" {
		t.Errorf("connector = %s", asJSON(els[1]))
	}
	if len(slides(doc)) != 2 || len(result.Warnings) != len(want) {
		t.Errorf("slide 2 should import without warnings: %v", result.Warnings)
	}
}

func TestImportReadsGroupsInTheirChildSpace(t *testing.T) {
	// A group drawn at half its child space: children shrink with it.
	b := deck(`<p:grpSp><p:nvGrpSpPr><p:cNvPr id="2" name="G"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>` +
		`<p:grpSpPr><a:xfrm rot="5400000"><a:off x="635000" y="635000"/><a:ext cx="1270000" cy="635000"/>` +
		`<a:chOff x="6350000" y="6350000"/><a:chExt cx="2540000" cy="1270000"/></a:xfrm></p:grpSpPr>` +
		`<p:sp><p:nvSpPr><p:cNvPr id="3" name="R"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>` +
		`<p:spPr><a:xfrm><a:off x="7620000" y="6350000"/><a:ext cx="1270000" cy="1270000"/></a:xfrm>` +
		`<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></p:spPr></p:sp>` +
		`</p:grpSp>`)
	doc, _ := importPptx(t, b.zip(t), nil)
	group := elements(slides(doc)[0])[1]
	if got, want := asJSON(group["frame"]), `{"height":100,"rotation":90,"width":200,"x":100,"y":100}`; got != want {
		t.Errorf("group frame = %s, want %s", got, want)
	}
	if got, want := asJSON(group["children"].([]any)[0].(map[string]any)["frame"]),
		`{"height":100,"width":100,"x":100,"y":0}`; got != want {
		t.Errorf("child frame = %s, want %s", got, want)
	}
}

func TestImportStoresAPictureOnceAndSkipsOneTooLarge(t *testing.T) {
	pic := `<p:pic><p:nvPicPr><p:cNvPr id="5" name="P" descr="Logo"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>` +
		`<p:blipFill><a:blip r:embed="%s"/><a:srcRect l="10000"/></p:blipFill>` +
		`<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="635000" cy="635000"/></a:xfrm></p:spPr></p:pic>`
	b := deck(fmt.Sprintf(pic, "rId2"), fmt.Sprintf(pic, "rId2")+fmt.Sprintf(pic, "rId4"))
	b["ppt/slides/_rels/slide2.xml.rels"] = rels(
		[3]string{"rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"},
		[3]string{"rId2", "image", "../media/image1.png"},
		[3]string{"rId4", "image", "../media/huge.png"},
	)
	b["ppt/media/image1.png"] = string(pngBytes(t, 2, 2))
	body := b.zip(t)
	// huge.png declares more than the picture limit; it is never read.
	body = appendRawEntry(t, body, "ppt/media/huge.png", pptxutil.MaxImageBytes+1)

	media := &mediaStore{}
	doc, result := importPptx(t, body, media)
	if len(media.files) != 1 || result.Pictures != 1 {
		t.Errorf("stored %d pictures (%d), want the shared one once", len(media.files), result.Pictures)
	}
	for _, slide := range slides(doc) {
		img := elements(slide)[1]
		if img["source"] != "pics/image1.png" || img["fit"] != "cover" || img["altText"] != "Logo" {
			t.Errorf("picture = %s", asJSON(img))
		}
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Slide != 2 ||
		result.Warnings[0].Message != "Pictures larger than 100 MiB were left out." {
		t.Errorf("warnings = %+v", result.Warnings)
	}

	// A store that fails is the server's fault, and fails the import.
	failing := &mediaStore{fail: errors.New("disk full")}
	_, err := pptxutil.ImportPptx(pptxutil.ImportPptxParams{
		Source: bytes.NewReader(body), Size: int64(len(body)), Out: io.Discard, StoreMedia: failing.store,
	})
	if err == nil || errors.Is(err, pptxutil.ErrNotPptx) {
		t.Errorf("failing store = %v, want its error", err)
	}
}

// appendRawEntry rebuilds body with one more entry that declares size bytes
// but holds a few.
func appendRawEntry(t *testing.T, body []byte, name string, size uint64) []byte {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(body), int64(len(body)))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for _, f := range zr.File {
		if err := zw.Copy(f); err != nil {
			t.Fatal(err)
		}
	}
	w, err := zw.CreateRaw(&zip.FileHeader{Name: name, Method: zip.Store, UncompressedSize64: size, CompressedSize64: 4})
	if err != nil {
		t.Fatal(err)
	}
	_, _ = w.Write([]byte("\x89PNG"))
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return out.Bytes()
}

func TestImportLeavesASlideItCannotReadEmpty(t *testing.T) {
	b := deck(`<p:sp>`, `<p:sp><p:nvSpPr><p:cNvPr id="2" name="R"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>`+
		`<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="6350" cy="6350"/></a:xfrm></p:spPr></p:sp>`)
	doc, result := importPptx(t, b.zip(t), nil)
	if got := len(slides(doc)); got != 2 {
		t.Fatalf("slides = %d", got)
	}
	if len(elements(slides(doc)[0])) != 0 || len(elements(slides(doc)[1])) != 2 {
		t.Errorf("slides = %s", asJSON(doc["slides"]))
	}
	if len(result.Warnings) != 1 || result.Warnings[0].Slide != 1 {
		t.Errorf("warnings = %+v", result.Warnings)
	}
}

func TestImportReadsSlideSizes(t *testing.T) {
	for _, c := range []struct {
		cx, cy int
		want   string
	}{
		{12192000, 6858000, `{"height":1080,"width":1920}`},
		{9144000, 6858000, `{"height":768,"width":1024}`},
		{9144000, 5143500, `{"height":1080,"width":1920}`},
		{6858000, 9144000, `{"height":2560,"width":1920}`},
		{0, 0, `{"height":1080,"width":1920}`},
	} {
		b := deck()
		b["ppt/presentation.xml"] = fmt.Sprintf(`<p:presentation %s><p:sldSz cx="%d" cy="%d"/></p:presentation>`, ns, c.cx, c.cy)
		doc, _ := importPptx(t, b.zip(t), nil)
		if got := asJSON(doc["size"]); got != c.want {
			t.Errorf("%d×%d EMU = %s, want %s", c.cx, c.cy, got, c.want)
		}
		if got := asJSON(doc["slides"]); got != `[]` {
			t.Errorf("slides = %s", got)
		}
	}
}

// importErr imports body and returns the error.
func importErr(body []byte) error {
	_, err := pptxutil.ImportPptx(pptxutil.ImportPptxParams{
		Source: bytes.NewReader(body), Size: int64(len(body)), Out: io.Discard,
	})
	return err
}

func TestImportRefusesWhatIsNotAPptx(t *testing.T) {
	notPresentation := pptxBuilder{"word/document.xml": "<w:document/>"}
	for name, body := range map[string][]byte{
		"empty":           {},
		"not a zip":       []byte("just some text, not an archive at all"),
		"no presentation": notPresentation.zip(t),
		"broken xml":      pptxBuilder{"ppt/presentation.xml": "<p:presentation"}.zip(t),
	} {
		if err := importErr(body); !errors.Is(err, pptxutil.ErrNotPptx) {
			t.Errorf("%s: %v, want ErrNotPptx", name, err)
		}
	}
}

func TestImportRefusesEntriesThatClimbOutOfThePackage(t *testing.T) {
	for _, name := range []string{"../evil.xml", "/etc/passwd", "ppt/../../evil", `ppt\slides\slide1.xml`, "C:/x.xml", "ppt//x"} {
		b := deck()
		b[name] = "x"
		if err := importErr(b.zip(t)); !errors.Is(err, pptxutil.ErrNotPptx) {
			t.Errorf("%q: %v, want ErrNotPptx", name, err)
		}
	}
}

func TestImportRefusesDuplicateEntries(t *testing.T) {
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for _, name := range []string{"ppt/presentation.xml", "PPT/Presentation.xml"} {
		w, _ := zw.Create(name)
		_, _ = w.Write([]byte(`<p:presentation ` + ns + `/>`))
	}
	_ = zw.Close()
	if err := importErr(out.Bytes()); !errors.Is(err, pptxutil.ErrNotPptx) {
		t.Errorf("duplicate entries: %v, want ErrNotPptx", err)
	}
}

func TestImportRefusesTooManyEntries(t *testing.T) {
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for i := range pptxutil.MaxImportEntries + 1 {
		if _, err := zw.CreateHeader(&zip.FileHeader{Name: fmt.Sprintf("e/%d", i), Method: zip.Store}); err != nil {
			t.Fatal(err)
		}
	}
	_ = zw.Close()
	if err := importErr(out.Bytes()); !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("too many entries: %v, want ErrTooLarge", err)
	}
}

func TestImportRefusesAZip64DirectoryClaimingTooManyEntries(t *testing.T) {
	// No entries at all: a zip64 record claiming a billion, its locator, and
	// the end record deferring to it.
	var b bytes.Buffer
	le := func(v any) { _ = binary.Write(&b, binary.LittleEndian, v) }
	le(uint32(0x06064b50))
	le(uint64(44))
	le(uint16(45))
	le(uint16(45))
	le(uint32(0))
	le(uint32(0))
	le(uint64(1_000_000_000))
	le(uint64(1_000_000_000))
	le(uint64(1 << 20))
	le(uint64(0))
	le(uint32(0x07064b50))
	le(uint32(0))
	le(uint64(0))
	le(uint32(1))
	le(uint32(0x06054b50))
	le(uint16(0))
	le(uint16(0))
	le(uint16(0xFFFF))
	le(uint16(0xFFFF))
	le(uint32(0xFFFFFFFF))
	le(uint32(0xFFFFFFFF))
	le(uint16(0))
	if err := importErr(b.Bytes()); !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("zip64 bomb: %v, want ErrTooLarge", err)
	}
}

func TestImportRefusesAPartThatUnpacksPastItsCap(t *testing.T) {
	// A few kilobytes that inflate past the XML cap.
	b := deck("")
	var out bytes.Buffer
	zw := zip.NewWriter(&out)
	for name, body := range b {
		if name == "ppt/slides/slide1.xml" {
			continue
		}
		w, _ := zw.Create(name)
		_, _ = w.Write([]byte(body))
	}
	w, _ := zw.Create("ppt/slides/slide1.xml")
	_, _ = io.WriteString(w, `<p:sld `+ns+`><p:cSld><p:spTree>`)
	chunk := bytes.Repeat([]byte(" "), 1<<20)
	for range pptxutil.MaxXMLPartBytes>>20 + 1 {
		_, _ = w.Write(chunk)
	}
	_, _ = io.WriteString(w, `</p:spTree></p:cSld></p:sld>`)
	_ = zw.Close()
	if out.Len() > 1<<20 {
		t.Fatalf("the bomb is %d bytes compressed", out.Len())
	}
	if err := importErr(out.Bytes()); !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("zip bomb: %v, want ErrTooLarge", err)
	}
}

func TestImportRefusesXMLNestedTooDeep(t *testing.T) {
	depth := pptxutil.MaxXMLDepth + 1
	b := deck(strings.Repeat("<a:x>", depth) + strings.Repeat("</a:x>", depth))
	if err := importErr(b.zip(t)); !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("deep XML: %v, want ErrTooLarge", err)
	}
}

func TestImportRefusesGroupsNestedTooDeep(t *testing.T) {
	open := `<p:grpSp><p:nvGrpSpPr><p:cNvPr id="2" name="G"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>` +
		`<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="10" cy="10"/><a:chOff x="0" y="0"/><a:chExt cx="10" cy="10"/></a:xfrm></p:grpSpPr>`
	depth := pptxutil.MaxGroupDepth + 2
	b := deck(strings.Repeat(open, depth) + strings.Repeat("</p:grpSp>", depth))
	if err := importErr(b.zip(t)); !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("deep groups: %v, want ErrTooLarge", err)
	}
}

func TestImportRefusesAMissingSourceOrOut(t *testing.T) {
	if _, err := pptxutil.ImportPptx(pptxutil.ImportPptxParams{Out: io.Discard}); err == nil {
		t.Error("no source: want an error")
	}
}

func TestImportRefusesAPartWithTooManyElements(t *testing.T) {
	b := deck(strings.Repeat("<a:x/>", pptxutil.MaxXMLElements+1))
	if err := importErr(b.zip(t)); !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("a slide of tiny elements: %v, want ErrTooLarge", err)
	}
}

func TestImportRefusesLayoutsThatTogetherHoldTooManyElements(t *testing.T) {
	// Each layout is under the part cap; kept together, they are past the
	// templates' cap.
	const layouts = 5
	perLayout := pptxutil.MaxTemplateElements/layouts + 1
	slideXML := make([]string, layouts)
	b := deck(slideXML...)
	for i := range layouts {
		layout := fmt.Sprintf("ppt/slideLayouts/big%d.xml", i)
		b[layout] = `<p:sldLayout ` + ns + `><p:cSld><p:spTree>` + strings.Repeat("<a:x/>", perLayout-10) +
			`</p:spTree></p:cSld></p:sldLayout>`
		b[fmt.Sprintf("ppt/slideLayouts/_rels/big%d.xml.rels", i)] =
			rels([3]string{"rId1", "slideMaster", "../slideMasters/slideMaster1.xml"})
		b[fmt.Sprintf("ppt/slides/_rels/slide%d.xml.rels", i+1)] =
			rels([3]string{"rId1", "slideLayout", fmt.Sprintf("../slideLayouts/big%d.xml", i)})
	}
	if err := importErr(b.zip(t)); !errors.Is(err, pptxutil.ErrTooLarge) {
		t.Errorf("many large layouts: %v, want ErrTooLarge", err)
	} else if !strings.Contains(err.Error(), "layouts and masters") {
		t.Errorf("many large layouts failed on another limit: %v", err)
	}
}
