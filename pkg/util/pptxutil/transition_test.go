package pptxutil_test

// cspell:ignore spd

import (
	"bytes"
	"fmt"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// transitionDeck fades by default, and gives some slides their own: a push,
// an explicit cut, a kind PowerPoint has no match for, a wipe, and a zoom
// longer than the editor allows.
const transitionDeck = `{
  "schemaVersion": 3,
  "title": "Moving",
  "size": {"width": 1920, "height": 1080},
  "transition": {"kind": "fade", "duration": 700},
  "slides": [
    {"id": "s1", "elements": []},
    {"id": "s2", "elements": [], "transition": {"kind": "push", "direction": "up", "duration": 1200}},
    {"id": "s3", "elements": [], "transition": {"kind": "none"}},
    {"id": "s4", "elements": [], "transition": {"kind": "cube", "duration": 900}},
    {"id": "s5", "elements": [], "transition": {"kind": "wipe", "direction": "right"}},
    {"id": "s6", "elements": [], "transition": {"kind": "zoom", "duration": 3000}}
  ]
}`

func TestExportWritesEachSlidesTransition(t *testing.T) {
	parts, result := export(t, transitionDeck, nil)
	if result.Slides != 6 {
		t.Fatalf("slides = %d, want 6", result.Slides)
	}
	slide := func(n int) string {
		body := parts.part(t, fmt.Sprintf("ppt/slides/slide%d.xml", n))
		wellFormed(t, fmt.Sprintf("slide %d", n), body)
		return body
	}
	// PowerPoint's own form: the exact duration for 2010 and later, the
	// nearest speed for anything older, after the color mapping.
	contains(t, "slide 1", slide(1),
		`<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr><mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">`+
			`<mc:Choice xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main" Requires="p14">`+
			`<p:transition spd="med" p14:dur="700"><p:fade/></p:transition></mc:Choice>`+
			`<mc:Fallback><p:transition spd="med"><p:fade/></p:transition></mc:Fallback></mc:AlternateContent></p:sld>`)
	contains(t, "slide 2", slide(2), `<p:transition spd="slow" p14:dur="1200"><p:push dir="u"/></p:transition>`)
	lacks(t, "slide 3", slide(3), `transition`)
	lacks(t, "slide 4", slide(4), `transition`)
	contains(t, "slide 5", slide(5), `<p:transition spd="fast" p14:dur="500"><p:wipe dir="r"/></p:transition>`)
	contains(t, "slide 6", slide(6), `<p:transition spd="slow" p14:dur="2000"><p:zoom/></p:transition>`)
}

func TestExportAppliesOnlyADefaultTransitionAheadOfTheSlides(t *testing.T) {
	deck := `{"schemaVersion": 3, "slides": [{"id": "s1", "elements": []}],
		"transition": {"kind": "fade"}}`
	parts, _ := export(t, deck, nil)
	lacks(t, "slide 1", parts.part(t, "ppt/slides/slide1.xml"), `transition`)
}

func TestImportReadsBackTheTransitionsTheExportWrote(t *testing.T) {
	var exported bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(transitionDeck), Out: &exported,
	}); err != nil {
		t.Fatal(err)
	}
	doc, result := importPptx(t, exported.Bytes(), nil)
	if len(result.Warnings) != 0 {
		t.Errorf("warnings = %v", result.Warnings)
	}
	// The deck's default lands on each slide that followed it.
	want := []string{
		`{"duration":700,"kind":"fade"}`,
		`{"direction":"up","duration":1200,"kind":"push"}`,
		`null`,
		`null`,
		`{"direction":"right","kind":"wipe"}`,
		`{"duration":2000,"kind":"zoom"}`,
	}
	got := slides(doc)
	if len(got) != len(want) {
		t.Fatalf("slides = %d, want %d", len(got), len(want))
	}
	for i, s := range got {
		if g := asJSON(s["transition"]); g != want[i] {
			t.Errorf("slide %d transition = %s, want %s", i+1, g, want[i])
		}
	}
}

func TestImportMapsPowerPointTransitions(t *testing.T) {
	const alternate = `<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">` +
		`<mc:Choice xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main" Requires="p14">%s</mc:Choice>` +
		`<mc:Fallback>%s</mc:Fallback></mc:AlternateContent>`
	cases := []struct {
		name, xml, want string
		warns           bool
	}{
		{"a push at medium speed", `<p:transition spd="med"><p:push dir="u"/></p:transition>`,
			`{"direction":"up","duration":750,"kind":"push"}`, false},
		{"a wipe at the default speed and direction", `<p:transition><p:wipe/></p:transition>`,
			`{"kind":"wipe"}`, false},
		{"a fade with a sound", `<p:transition spd="slow"><p:sndAc><p:stSnd><p:snd r:embed="rId9" name="chime"/></p:stSnd></p:sndAc><p:fade/></p:transition>`,
			`{"duration":1000,"kind":"fade"}`, false},
		{"a zoom out", `<p:transition><p:zoom dir="out"/></p:transition>`,
			`{"kind":"zoom"}`, false},
		{"PowerPoint's exact duration", fmt.Sprintf(alternate,
			`<p:transition spd="slow" p14:dur="1600"><p:push dir="r"/></p:transition>`,
			`<p:transition spd="slow"><p:push dir="r"/></p:transition>`),
			`{"direction":"right","duration":1600,"kind":"push"}`, false},
		{"a 2010 effect falls back to its plainer one", fmt.Sprintf(alternate,
			`<p:transition spd="slow" p14:dur="3400"><p14:vortex dir="r"/></p:transition>`,
			`<p:transition spd="slow"><p:fade/></p:transition>`),
			`{"duration":2000,"kind":"fade"}`, false},
		{"an effect with no match", `<p:transition><p:cover dir="r"/></p:transition>`,
			`null`, true},
		{"timing alone is no effect", `<p:transition advTm="3000"/>`, `null`, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			b := deck("")
			b["ppt/slides/slide1.xml"] = strings.Replace(b["ppt/slides/slide1.xml"], `</p:cSld>`,
				`</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>`+tc.xml, 1)
			doc, result := importPptx(t, b.zip(t), &mediaStore{})
			if got := asJSON(slides(doc)[0]["transition"]); got != tc.want {
				t.Errorf("transition = %s, want %s", got, tc.want)
			}
			var warned bool
			for _, w := range result.Warnings {
				warned = warned || strings.Contains(w.Message, "transition")
			}
			if warned != tc.warns {
				t.Errorf("warned = %v, want %v (%v)", warned, tc.warns, result.Warnings)
			}
		})
	}
}
