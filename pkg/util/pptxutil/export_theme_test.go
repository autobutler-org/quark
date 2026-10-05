package pptxutil_test

// cspell:ignore clr srgb

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"reflect"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// fixture is the path of one of quark_slides' golden .qslide files.
func fixture(name string) string {
	return "../../../packages/quark_slides/test/fixtures/" + name
}

// exportFile exports a fixture, streamed from disk as the handler streams it.
func exportFile(t *testing.T, name string) (pptx, pptxutil.ExportQslideResult) {
	t.Helper()
	f, err := os.Open(fixture(name))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var out bytes.Buffer
	result, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{Source: f, Out: &out})
	if err != nil {
		t.Fatalf("ExportQslide(%s): %v", name, err)
	}
	return unzip(t, out.Bytes()), result
}

func TestExportReadsTheGoldenVersion3Fixture(t *testing.T) {
	parts, result := exportFile(t, "sample.qslide")
	if result.Slides != 4 {
		t.Errorf("slides = %d, want 4", result.Slides)
	}
	for name, body := range parts {
		if strings.HasSuffix(name, ".xml") || strings.HasSuffix(name, ".rels") {
			wellFormed(t, name, body)
		}
	}

	// The stored theme is the package's theme: its ten roles and two fonts.
	theme := parts.part(t, "ppt/theme/theme1.xml")
	contains(t, "theme", theme,
		`name="Sample"`,
		`<a:dk1><a:srgbClr val="3B2A20"/></a:dk1><a:lt1><a:srgbClr val="FFF8F0"/></a:lt1>`,
		`<a:dk2><a:srgbClr val="7A5C48"/></a:dk2><a:lt2><a:srgbClr val="F6E7D8"/></a:lt2>`,
		`<a:accent1><a:srgbClr val="C2410C"/></a:accent1><a:accent2><a:srgbClr val="B45309"/></a:accent2>`,
		`<a:accent3><a:srgbClr val="A16207"/></a:accent3><a:accent4><a:srgbClr val="BE123C"/></a:accent4>`,
		`<a:accent5><a:srgbClr val="9D174D"/></a:accent5><a:accent6><a:srgbClr val="4D7C0F"/></a:accent6>`,
		`<a:majorFont><a:latin typeface="Georgia"/>`,
		`<a:minorFont><a:latin typeface="Inter"/>`)

	// Slide 4 is built on a layout: a title placeholder in the theme's title
	// style with its own role color, an empty body placeholder, and a shape
	// in role colors.
	slide := parts.part(t, "ppt/slides/slide4.xml")
	contains(t, "slide 4", slide,
		`<a:rPr lang="en-US" sz="3000" dirty="0"><a:solidFill><a:srgbClr val="B45309"/></a:solidFill>`+
			`<a:latin typeface="Georgia"/><a:cs typeface="Georgia"/></a:rPr><a:t>Agenda</a:t>`,
		`<a:endParaRPr lang="en-US" sz="1800" dirty="0"><a:solidFill><a:srgbClr val="3B2A20"/></a:solidFill>`+
			`<a:latin typeface="Inter"/>`,
		`<a:solidFill><a:srgbClr val="C2410C"/></a:solidFill><a:ln w="12700"><a:solidFill><a:srgbClr val="3B2A20"/>`)
	lacks(t, "slide 4", slide, `theme:`)
	// A slide with no background of its own shows the master's, which is the
	// theme's background role.
	lacks(t, "slide 4", slide, `<p:bg>`)
	contains(t, "master", parts.part(t, "ppt/slideMasters/slideMaster1.xml"), `<a:schemeClr val="bg1"/>`)

	// The deck fades from slide to slide, except slide 4, which wipes.
	contains(t, "slide 1", parts.part(t, "ppt/slides/slide1.xml"),
		`<p:transition spd="med" p14:dur="700"><p:fade/></p:transition>`)
	contains(t, "slide 4", slide, `<p:transition spd="slow" p14:dur="1200"><p:wipe dir="r"/></p:transition>`)
}

func TestExportReadsTheGoldenVersion2Fixture(t *testing.T) {
	parts, result := exportFile(t, "v2_sample.qslide")
	if result.Slides != 4 {
		t.Errorf("slides = %d, want 4", result.Slides)
	}
	contains(t, "theme", parts.part(t, "ppt/theme/theme1.xml"), `name="Sample"`)
	// Version 2 had no transitions: every slide cuts.
	for i := 1; i <= 4; i++ {
		lacks(t, fmt.Sprintf("slide %d", i), parts.part(t, fmt.Sprintf("ppt/slides/slide%d.xml", i)), `transition`)
	}
}

func TestExportReadsTheGoldenVersion1Fixture(t *testing.T) {
	parts, result := exportFile(t, "v1_sample.qslide")
	if result.Slides != 3 {
		t.Errorf("slides = %d, want 3", result.Slides)
	}
	// "themes/default" names no built-in theme, so the deck has none: the
	// plain scheme, and unset text left to inherit it.
	contains(t, "theme", parts.part(t, "ppt/theme/theme1.xml"),
		`<a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>`)
	contains(t, "slide 1", parts.part(t, "ppt/slides/slide1.xml"),
		`<a:rPr lang="en-US" sz="1800" dirty="0"></a:rPr><a:t>Grouped</a:t>`)
}

func TestExportReadsAFileFromANewerWriterOfTheSameVersion(t *testing.T) {
	parts, result := exportFile(t, "future_fields.qslide")
	if result.Slides != 1 {
		t.Errorf("slides = %d, want 1", result.Slides)
	}
	// A role this version does not know is dropped from the scheme, and the
	// rest of the theme still applies.
	theme := parts.part(t, "ppt/theme/theme1.xml")
	contains(t, "theme", theme, `<a:accent1><a:srgbClr val="3366FF"/></a:accent1>`)
	lacks(t, "theme", theme, `123456`)
}

func TestExportRefusesTheNewerSchemaFixture(t *testing.T) {
	f, err := os.Open(fixture("newer_schema.qslide"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	_, err = pptxutil.ExportQslide(pptxutil.ExportQslideParams{Source: f, Out: io.Discard})
	if !errors.Is(err, pptxutil.ErrNotQslide) || !strings.Contains(err.Error(), "schema version 6") {
		t.Errorf("err = %v, want ErrNotQslide naming schema version 6", err)
	}
}

// themedDeck has a theme and an element of every kind in role colors.
const themedDeck = `{
  "schemaVersion": 2,
  "title": "Themed",
  "size": {"width": 1920, "height": 1080},
  "theme": {
    "id": "t", "name": "Ours & co",
    "colors": {"background": "#101010", "text": "#EEEEEE", "background2": "#202020", "text2": "#AAAAAA",
               "accent1": "#110000", "accent2": "#220000", "accent3": "#330000", "accent4": "#440000",
               "accent5": "#550000", "accent6": "theme:accent1"},
    "headingFont": "Georgia",
    "title": {"fontSize": 64, "color": "theme:accent2", "heading": true},
    "subtitle": {"fontSize": 44, "color": "theme:text2"},
    "body": {"fontSize": 30}
  },
  "slides": [
    {"id": "s1", "layout": "title", "background": {"color": "theme:background2"}, "elements": [
      {"id": "t", "type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
       "paragraphs": [{"runs": [{"text": "Title"}]}], "slot": "title", "textRole": "title"},
      {"id": "u", "type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
       "paragraphs": [{"runs": [{"text": "Sub"}]}], "slot": "subtitle", "textRole": "subtitle"},
      {"id": "b", "type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
       "paragraphs": [{"runs": [{"text": "Own", "fontSize": 20, "fontFamily": "Inter", "color": "#123456"},
                                {"text": "Role", "color": "theme:accent3"},
                                {"text": "Lost", "color": "theme:accent9"}]}]},
      {"id": "r", "type": "shape", "kind": "rectangle", "frame": {"x": 0, "y": 0, "width": 10, "height": 10},
       "fill": "theme:accent4", "stroke": {"color": "theme:accent6"}},
      {"id": "l", "type": "line", "frame": {"x": 0, "y": 0, "width": 10, "height": 10},
       "stroke": {"color": "theme:accent5"}}
    ]},
    {"id": "s2", "elements": []}
  ]
}`

func TestExportResolvesRoleColorsAgainstTheStoredTheme(t *testing.T) {
	parts, _ := export(t, themedDeck, nil)
	slide := parts.part(t, "ppt/slides/slide1.xml")
	srgb := func(rgb string) string { return `<a:srgbClr val="` + rgb + `"/>` }
	contains(t, "slide", slide,
		`<p:bg><p:bgPr><a:solidFill>`+srgb("202020"),
		// A run's own role color, and a role this version does not know,
		// which reads as text.
		srgb("330000")+`</a:solidFill></a:rPr><a:t>Role</a:t>`,
		srgb("EEEEEE")+`</a:solidFill></a:rPr><a:t>Lost</a:t>`,
		`<a:solidFill>`+srgb("440000")+`</a:solidFill><a:ln w="12700"><a:solidFill>`+srgb("3366FF"),
		`<a:ln w="12700"><a:solidFill>`+srgb("550000"))
	lacks(t, "slide", slide, `theme:`)
	// A role color inside the palette is that role's light-theme fallback,
	// as the codec reads it.
	contains(t, "theme", parts.part(t, "ppt/theme/theme1.xml"),
		`name="Ours &amp; co"`, `<a:accent6>`+srgb("3366FF")+`</a:accent6>`,
		`<a:majorFont><a:latin typeface="Georgia"/>`, `<a:minorFont><a:latin typeface="Arial"/>`)
}

func TestExportStylesTextFromItsRoleInTheTheme(t *testing.T) {
	parts, _ := export(t, themedDeck, nil)
	slide := parts.part(t, "ppt/slides/slide1.xml")
	contains(t, "slide", slide,
		// The title placeholder takes the title style: 64 units, the heading
		// font, the title's role color.
		`<a:rPr lang="en-US" sz="3200" dirty="0"><a:solidFill><a:srgbClr val="220000"/></a:solidFill>`+
			`<a:latin typeface="Georgia"/><a:cs typeface="Georgia"/></a:rPr><a:t>Title</a:t>`,
		// The subtitle, in the body font, which this theme leaves to the
		// default.
		`<a:rPr lang="en-US" sz="2200" dirty="0"><a:solidFill><a:srgbClr val="AAAAAA"/></a:solidFill></a:rPr><a:t>Sub</a:t>`,
		// An ordinary box is body text; what a run sets itself wins.
		`<a:rPr lang="en-US" sz="1000" dirty="0"><a:solidFill><a:srgbClr val="123456"/></a:solidFill>`+
			`<a:latin typeface="Inter"/><a:cs typeface="Inter"/></a:rPr><a:t>Own</a:t>`,
		`<a:rPr lang="en-US" sz="1500" dirty="0"><a:solidFill><a:srgbClr val="330000"/>`)
}

func TestExportGivesAVersion1ThemeReferenceItsBuiltInTheme(t *testing.T) {
	deck := `{"schemaVersion": 1, "theme": "dark", "slides": [{"id": "s1", "elements": [
		{"id": "t", "type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
		 "paragraphs": [{"runs": [{"text": "Hi"}]}]}]}]}`
	parts, _ := export(t, deck, nil)
	contains(t, "theme", parts.part(t, "ppt/theme/theme1.xml"),
		`name="Dark"`, `<a:lt1><a:srgbClr val="121318"/></a:lt1>`, `<a:accent1><a:srgbClr val="7AA2FF"/></a:accent1>`)
	contains(t, "slide", parts.part(t, "ppt/slides/slide1.xml"),
		`<a:rPr lang="en-US" sz="1800" dirty="0"><a:solidFill><a:srgbClr val="F3F4F6"/></a:solidFill></a:rPr><a:t>Hi</a:t>`)

	// A version 2 theme must be an object; a string there is no theme.
	parts, _ = export(t, strings.Replace(deck, `"schemaVersion": 1`, `"schemaVersion": 2`, 1), nil)
	contains(t, "theme", parts.part(t, "ppt/theme/theme1.xml"), `<a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>`)
}

func TestExportResolvesRoleColorsWithoutATheme(t *testing.T) {
	deck := `{"schemaVersion": 2, "slides": [{"id": "s1", "elements": [
		{"id": "r", "type": "shape", "kind": "rectangle", "frame": {"x": 0, "y": 0, "width": 10, "height": 10},
		 "fill": "theme:accent1"},
		{"id": "t", "type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, "textRole": "title",
		 "paragraphs": [{"runs": [{"text": "Hi"}]}]}]}]}`
	parts, _ := export(t, deck, nil)
	slide := parts.part(t, "ppt/slides/slide1.xml")
	// The light theme's fallback, and its title size; the text color is left
	// to the package's scheme, as a canvas leaves it to the host.
	contains(t, "slide", slide, `<a:srgbClr val="3366FF"/>`, `<a:rPr lang="en-US" sz="3000" dirty="0"></a:rPr><a:t>Hi</a:t>`)
}

func TestExportAppliesOnlyAThemeAheadOfTheSlides(t *testing.T) {
	// The editor writes the theme before the slides. One after them would
	// restyle slides already written, so it is not applied at all.
	deck := `{"schemaVersion": 2, "slides": [{"id": "s1", "elements": [
		{"id": "r", "type": "shape", "kind": "rectangle", "frame": {"x": 0, "y": 0, "width": 10, "height": 10},
		 "fill": "theme:accent1"}]}],
		"theme": {"id": "late", "colors": {"accent1": "#ABCDEF"}}}`
	parts, _ := export(t, deck, nil)
	lacks(t, "slide", parts.part(t, "ppt/slides/slide1.xml"), `ABCDEF`)
	lacks(t, "theme", parts.part(t, "ppt/theme/theme1.xml"), `ABCDEF`)
}

func TestImportReadsBackAThemedDeckWithItsColorsResolved(t *testing.T) {
	var exported bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(themedDeck), Out: &exported,
	}); err != nil {
		t.Fatal(err)
	}
	got, result := importPptx(t, exported.Bytes(), nil)
	if len(result.Warnings) != 0 {
		t.Errorf("warnings = %+v", result.Warnings)
	}
	// An import writes version 1: no theme, every color literal.
	if got["schemaVersion"] != float64(1) || got["theme"] != nil {
		t.Errorf("schemaVersion = %v, theme = %v", got["schemaVersion"], got["theme"])
	}
	want := `[
	  {"background": {"color": "#202020"}, "elements": [
	    {"type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
	     "paragraphs": [{"runs": [{"text": "Title", "fontSize": 64, "fontFamily": "Georgia", "color": "#220000"}]}]},
	    {"type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
	     "paragraphs": [{"runs": [{"text": "Sub", "fontSize": 44, "fontFamily": "Arial", "color": "#AAAAAA"}]}]},
	    {"type": "text", "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
	     "paragraphs": [{"runs": [
	       {"text": "Own", "fontSize": 20, "fontFamily": "Inter", "color": "#123456"},
	       {"text": "Role", "fontSize": 30, "fontFamily": "Arial", "color": "#330000"},
	       {"text": "Lost", "fontSize": 30, "fontFamily": "Arial", "color": "#EEEEEE"}]}]},
	    {"type": "shape", "kind": "rectangle", "frame": {"x": 0, "y": 0, "width": 10, "height": 10},
	     "fill": "#440000", "stroke": {"color": "#3366FF", "width": 2}},
	    {"type": "line", "frame": {"x": 0, "y": 0, "width": 10, "height": 10},
	     "stroke": {"color": "#550000", "width": 2}}
	  ]},
	  {"background": {"color": "#101010"}, "elements": []}
	]`
	var wantSlides any
	if err := json.Unmarshal([]byte(want), &wantSlides); err != nil {
		t.Fatal(err)
	}
	if gotSlides := withoutIDs(got["slides"]); !reflect.DeepEqual(gotSlides, wantSlides) {
		gotJSON, _ := json.MarshalIndent(gotSlides, "", "  ")
		t.Errorf("round trip:\n%s", gotJSON)
	}
}
