package pptxutil

// cspell:ignore autofit descr fmla prst srgb xfrm

import (
	"fmt"
	"math"
	"strings"
)

// The editor's defaults for what a .qslide leaves unset.
const (
	// defaultFontSize is the size of a run that sets none, in slide units.
	defaultFontSize = 36.0
	// defaultLineSpacing is a paragraph's line height as a multiple of its
	// font size when it sets none. PowerPoint's single spacing (100%) is the
	// same 1.2 times the font size, so a spacing converts by dividing by it.
	defaultLineSpacing = 1.2
	// defaultCornerRatio is a rounded rectangle's corner radius, as a share
	// of its shorter side, when it sets none.
	defaultCornerRatio = 0.15
	// listGutterRatio is how far a list item's text is indented past its
	// marker, as a multiple of its font size.
	listGutterRatio = 1.5
	// placeholderFill is the gray a picture that could not be embedded is
	// drawn in.
	placeholderFill = "D9D9D9"
)

// shapeGeometry maps a shape kind to its preset geometry.
var shapeGeometry = map[string]string{
	"rectangle":        "rect",
	"roundedRectangle": "roundRect",
	"ellipse":          "ellipse",
	"triangle":         "triangle",
	"diamond":          "diamond",
	"arrow":            "rightArrow",
	"star":             "star5",
}

// strokeDash maps a stroke's dash to its preset dash.
var strokeDash = map[string]string{"dash": "dash", "dot": "sysDot", "dashDot": "dashDot"}

// genericFonts maps the generic families the editor offers to a font every
// PowerPoint has.
var genericFonts = map[string]string{
	"sans-serif": "Arial",
	"serif":      "Times New Roman",
	"monospace":  "Courier New",
}

// writeSlidePart writes the slide: its background, then its elements back to
// front, which is the shape tree's order, then its transition, or the deck's.
func (s *slideWriter) writeSlidePart(slide qslideSlide) error {
	s.out.put(xmlHeader + `<p:sld` + pmlNamespaces + `><p:cSld>`)
	var bgImage string
	if bg := slide.Background; bg != nil {
		if c, ok := resolveColor(bg.Color, s.theme); ok {
			s.out.put(`<p:bg><p:bgPr>`)
			s.out.put(solidFill(c, 1))
			s.out.put(`<a:effectLst/></p:bgPr></p:bg>`)
		}
		bgImage = bg.Image
	}
	s.out.put(`<p:spTree>` + emptyGroup)
	if bgImage != "" {
		// A background holds one fill, so an image goes in as a picture
		// covering the slide behind everything, over the color.
		full := qslideFrame{Width: float64(s.cx) / s.scale, Height: float64(s.cy) / s.scale}
		s.writePicture(qslideElement{Type: typeImage, Frame: full, Source: bgImage, Fit: "cover", AltText: "Background"})
	}
	for _, el := range slide.Elements {
		s.writeElement(el)
	}
	s.out.put(`</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>`)
	transition := slide.Transition
	if transition == nil {
		transition = s.transition
	}
	s.out.put(transitionXML(transition) + `</p:sld>`)
	return s.out.Flush()
}

// writeElement writes one element. A type this writer does not know, or a
// shape of an unknown kind, is left out.
func (s *slideWriter) writeElement(el qslideElement) {
	switch el.Type {
	case typeText:
		s.writeTextBox(el)
	case typeShape:
		if prst, ok := shapeGeometry[el.Kind]; ok {
			s.writeShape(el, prst)
		}
	case typeImage:
		s.writePicture(el)
	case typeLine:
		s.writeLine(el)
	case typeGroup:
		s.writeGroup(el)
	case typeTable:
		s.writeTable(el)
	case typeChart:
		s.writeChart(el)
	}
}

// id returns the next shape id on the slide.
func (s *slideWriter) id() int {
	id := s.nextID
	s.nextID++
	return id
}

// nonVisual writes an element's id and name, and its description when given.
func (s *slideWriter) nonVisual(id int, name, descr string) {
	s.out.printf(`<p:cNvPr id="%d" name="%s %d"`, id, name, id)
	if descr != "" {
		s.out.put(` descr="`)
		s.out.text(descr)
		s.out.put(`"`)
	}
	s.out.put(`/>`)
}

// xfrm writes a frame's position, size, rotation and flips. extra goes inside
// the element after ext, for a group's child extents.
func (s *slideWriter) xfrm(f qslideFrame, attrs, extra string) {
	s.transform("a:xfrm", f, attrs, extra)
}

// transform writes a frame as xfrm does, in the element tag: a graphic
// frame's is p:xfrm.
func (s *slideWriter) transform(tag string, f qslideFrame, attrs, extra string) {
	s.out.put(`<` + tag)
	if rot := rotation(f.Rotation); rot != 0 {
		s.out.printf(` rot="%d"`, rot)
	}
	s.out.put(attrs)
	s.out.printf(`><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/>`,
		s.emu(f.X), s.emu(f.Y), s.size(f.Width), s.size(f.Height))
	s.out.put(extra + `</` + tag + `>`)
}

// size is a non-negative extent in EMU.
func (s *slideWriter) size(v float64) int64 { return max(s.emu(v), 0) }

// rotation converts clockwise degrees to OOXML's 60,000ths of a degree,
// within one turn.
func rotation(degrees float64) int64 {
	const turn = 21_600_000
	rot := int64(math.Round(degrees*60_000)) % turn
	if rot < 0 {
		rot += turn
	}
	return rot
}

// writeShape writes a filled and outlined preset shape.
func (s *slideWriter) writeShape(el qslideElement, prst string) {
	opacity := opacityOf(el.Opacity)
	s.out.put(`<p:sp><p:nvSpPr>`)
	s.nonVisual(s.id(), "Shape", "")
	s.out.put(`<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>`)
	s.xfrm(el.Frame, "", "")
	s.out.put(`<a:prstGeom prst="` + prst + `"><a:avLst>` + s.adjustments(el) + `</a:avLst></a:prstGeom>`)
	if c, ok := resolveColor(el.Fill, s.theme); ok {
		s.out.put(solidFill(c, opacity))
	} else {
		s.out.put(`<a:noFill/>`)
	}
	if el.Stroke != nil {
		s.writeLineProps("a:ln", *el.Stroke, opacity, "", "")
	} else {
		s.out.put(`<a:ln><a:noFill/></a:ln>`)
	}
	s.out.put(`</p:spPr></p:sp>`)
}

// adjustments are the guide values that make a preset match the editor's
// drawing of the same kind.
func (s *slideWriter) adjustments(el qslideElement) string {
	w, h := el.Frame.Width, el.Frame.Height
	shorter := math.Min(w, h)
	switch el.Kind {
	case "roundedRectangle":
		// The radius as a share of the shorter side; 50,000 is a half.
		ratio := defaultCornerRatio
		if el.CornerRadius != nil && shorter > 0 {
			ratio = math.Min(*el.CornerRadius/shorter, 0.5)
		}
		return fmt.Sprintf(`<a:gd name="adj" fmla="val %d"/>`, int64(math.Round(math.Max(ratio, 0)*100_000)))
	case "arrow":
		// The editor's shaft is the middle 40% of the height and its head the
		// last 40% of the width; the head length is a share of the shorter
		// side.
		head := 40_000.0
		if shorter > 0 {
			head = 0.4 * w / shorter * 100_000
		}
		return fmt.Sprintf(`<a:gd name="adj1" fmla="val 40000"/><a:gd name="adj2" fmla="val %d"/>`, int64(math.Round(head)))
	case "star":
		// The editor's inner corners sit at 0.4 of the outer radius; 50,000
		// is the whole radius.
		return `<a:gd name="adj" fmla="val 20000"/>`
	}
	return ""
}

// writeLineProps writes an outline as the element tag — a:ln, or a table
// cell's a:lnL, a:lnR, a:lnT or a:lnB: its width, color at opacity, dash,
// and the given head and tail ends.
func (s *slideWriter) writeLineProps(tag string, stroke qslideStroke, opacity float64, head, tail string) {
	width := 2.0
	if stroke.Width != nil {
		width = math.Max(*stroke.Width, 0)
	}
	c := color{rgb: "000000", alpha: 1}
	if stroke.Color != nil {
		if parsed, ok := resolveColor(*stroke.Color, s.theme); ok {
			c = parsed
		}
	}
	dash, _ := stroke.Dash.(string)
	prstDash, dashed := strokeDash[dash]
	s.out.printf(`<%s w="%d"`, tag, clampEMU(math.Round(width*s.scale), 0, 20_116_800))
	if dash == "dot" {
		// The editor draws dots round.
		s.out.put(` cap="rnd"`)
	}
	s.out.put(`>` + solidFill(c, opacity))
	if dashed {
		s.out.put(`<a:prstDash val="` + prstDash + `"/>`)
	}
	s.out.put(head + tail + `</` + tag + `>`)
}

// writeLine writes a straight line or arrow across its frame's diagonal: top
// left to bottom right, or bottom left to top right when flipped.
func (s *slideWriter) writeLine(el qslideElement) {
	stroke := qslideStroke{}
	if el.Stroke != nil {
		stroke = *el.Stroke
	}
	flip := ""
	if el.Flipped {
		flip = ` flipV="1"`
	}
	s.out.put(`<p:cxnSp><p:nvCxnSpPr>`)
	s.nonVisual(s.id(), "Line", "")
	s.out.put(`<p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr><p:spPr>`)
	s.xfrm(el.Frame, flip, "")
	s.out.put(`<a:prstGeom prst="line"><a:avLst/></a:prstGeom>`)
	s.writeLineProps("a:ln", stroke, opacityOf(el.Opacity), lineEnd("headEnd", el.StartCap), lineEnd("tailEnd", el.EndCap))
	s.out.put(`</p:spPr></p:cxnSp>`)
}

// lineEnd is an arrowhead at one end of a line, or nothing.
func lineEnd(name, lineCap string) string {
	if lineCap != "arrow" {
		return ""
	}
	return `<a:` + name + ` type="triangle" w="med" len="med"/>`
}

// writePicture writes a picture fitted to its frame as the editor fits it, or
// a gray placeholder carrying its alt text when it could not be embedded.
func (s *slideWriter) writePicture(el qslideElement) {
	// embedAll put every picture in the package before the slide was
	// started, so this only looks it up.
	part := s.media[el.Source]
	if part == nil {
		s.out.put(`<p:sp><p:nvSpPr>`)
		s.nonVisual(s.id(), "Picture", el.AltText)
		s.out.put(`<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>`)
		s.xfrm(el.Frame, "", "")
		s.out.put(`<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>`)
		s.out.put(solidFill(color{rgb: placeholderFill, alpha: 1}, 1) + `<a:ln><a:noFill/></a:ln></p:spPr></p:sp>`)
		return
	}
	rel, ok := s.rels[part.name]
	if !ok {
		rel = fmt.Sprintf("rId%d", s.firstImageRel+len(s.relOrder))
		s.rels[part.name] = rel
		s.relOrder = append(s.relOrder, part.name)
	}

	frame, crop := fitPicture(el.Frame, el.Fit, float64(part.width), float64(part.height))
	s.out.put(`<p:pic><p:nvPicPr>`)
	s.nonVisual(s.id(), "Picture", el.AltText)
	s.out.put(`<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>`)
	s.out.put(`<p:blipFill><a:blip r:embed="` + rel + `"/>` + crop + `<a:stretch><a:fillRect/></a:stretch></p:blipFill>`)
	s.out.put(`<p:spPr>`)
	s.xfrm(frame, "", "")
	s.out.put(`<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>`)
}

// fitPicture fits a picture iw by ih pixels to frame as fit says: "fill"
// stretches it, "cover" crops it to fill the frame, and anything else
// ("contain") shrinks the frame about its center to the picture's shape.
// It returns the frame to draw in and the <a:srcRect> crop, if any.
func fitPicture(frame qslideFrame, fit string, iw, ih float64) (qslideFrame, string) {
	if fit == "fill" || frame.Width <= 0 || frame.Height <= 0 {
		return frame, ""
	}
	imageAspect, frameAspect := iw/ih, frame.Width/frame.Height
	if fit == "cover" {
		// The share of each side cut away, in 1,000ths of a percent.
		if imageAspect > frameAspect {
			cut := int64(math.Round((1 - frameAspect/imageAspect) / 2 * 100_000))
			return frame, fmt.Sprintf(`<a:srcRect l="%d" r="%d"/>`, cut, cut)
		}
		cut := int64(math.Round((1 - imageAspect/frameAspect) / 2 * 100_000))
		if cut == 0 {
			return frame, ""
		}
		return frame, fmt.Sprintf(`<a:srcRect t="%d" b="%d"/>`, cut, cut)
	}
	fitted := frame
	if imageAspect > frameAspect {
		fitted.Height = frame.Width / imageAspect
		fitted.Y += (frame.Height - fitted.Height) / 2
	} else {
		fitted.Width = frame.Height * imageAspect
		fitted.X += (frame.Width - fitted.Width) / 2
	}
	return fitted, ""
}

// writeGroup writes a group. Its children's frames are group-local — measured
// from the group's top-left corner before its rotation — which is a child
// coordinate space at the origin the group's own size.
func (s *slideWriter) writeGroup(el qslideElement) {
	s.out.put(`<p:grpSp><p:nvGrpSpPr>`)
	s.nonVisual(s.id(), "Group", "")
	s.out.put(`<p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>`)
	s.xfrm(el.Frame, "", fmt.Sprintf(`<a:chOff x="0" y="0"/><a:chExt cx="%d" cy="%d"/>`,
		s.size(el.Frame.Width), s.size(el.Frame.Height)))
	s.out.put(`</p:grpSpPr>`)
	for _, child := range el.Children {
		s.writeElement(child)
	}
	s.out.put(`</p:grpSp>`)
}

// writeTextBox writes a text box: no fill or outline, no insets — the editor
// draws text flush with its frame — and its paragraphs, styled where they set
// nothing themselves by the theme's style for the box's text role.
func (s *slideWriter) writeTextBox(el qslideElement) {
	style := roleStyle(s.theme, el.TextRole)
	s.out.put(`<p:sp><p:nvSpPr>`)
	s.nonVisual(s.id(), "TextBox", "")
	s.out.put(`<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr>`)
	s.xfrm(el.Frame, "", "")
	s.out.put(`<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>`)

	anchor := map[string]string{"middle": "ctr", "bottom": "b"}[el.Anchor]
	if anchor == "" {
		anchor = "t"
	}
	fit := `<a:spAutoFit/>`
	switch el.AutoFit {
	case "fixed":
		fit = `<a:noAutofit/>`
	case "shrink":
		fit = `<a:normAutofit/>`
	}
	s.out.put(`<p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="` + anchor +
		`" rtlCol="0">` + fit + `</a:bodyPr><a:lstStyle/>`)
	if len(el.Paragraphs) == 0 {
		s.out.put(`<a:p>`)
		s.writeRunProps("a:endParaRPr", qslideRun{}, style)
		s.out.put(`</a:p>`)
	}
	for _, p := range el.Paragraphs {
		s.writeParagraph(p, style)
	}
	s.out.put(`</p:txBody></p:sp>`)
}

// writeParagraph writes one paragraph: its alignment, line spacing and list
// marker, then its runs. The paragraph's end takes the last run's style, so an
// empty line is as tall as the text around it.
func (s *slideWriter) writeParagraph(p qslideParagraph, style runStyle) {
	s.out.put(`<a:p><a:pPr`)
	size := style.size
	if len(p.Runs) > 0 && p.Runs[0].FontSize != nil {
		size = *p.Runs[0].FontSize
	}
	if p.List == "bullet" || p.List == "numbered" {
		gutter := s.emu(size * listGutterRatio)
		s.out.printf(` marL="%d" indent="%d"`, gutter, -gutter)
	}
	if algn := map[string]string{"center": "ctr", "end": "r", "justify": "just"}[p.Align]; algn != "" {
		s.out.put(` algn="` + algn + `"`)
	} else {
		s.out.put(` algn="l"`)
	}
	s.out.put(`>`)
	if p.LineSpacing != nil && *p.LineSpacing > 0 {
		s.out.printf(`<a:lnSpc><a:spcPct val="%d"/></a:lnSpc>`,
			clampEMU(math.Round(*p.LineSpacing/defaultLineSpacing*100_000), 0, 13_200_000))
	}
	switch p.List {
	case "bullet":
		s.out.put(`<a:buFont typeface="Arial"/><a:buChar char="•"/>`)
	case "numbered":
		s.out.put(`<a:buFont typeface="+mj-lt"/><a:buAutoNum type="arabicPeriod"/>`)
	default:
		s.out.put(`<a:buNone/>`)
	}
	s.out.put(`</a:pPr>`)

	last := qslideRun{}
	for _, run := range p.Runs {
		last = run
		if run.Text == "" {
			continue
		}
		s.out.put(`<a:r>`)
		s.writeRunProps("a:rPr", run, style)
		s.out.put(`<a:t>`)
		s.out.text(run.Text)
		s.out.put(`</a:t></a:r>`)
	}
	s.writeRunProps("a:endParaRPr", last, style)
	s.out.put(`</a:p>`)
}

// writeRunProps writes a run's style as the element tag: size always, and the
// color and font the run sets, or else style's, so what neither sets inherits
// the package theme's.
func (s *slideWriter) writeRunProps(tag string, run qslideRun, style runStyle) {
	size := style.size
	if run.FontSize != nil && *run.FontSize > 0 {
		size = *run.FontSize
	}
	s.out.printf(`<%s lang="en-US" sz="%d"`, tag, s.fontSize(size))
	for _, attr := range []struct {
		on   bool
		attr string
	}{
		{run.Bold, ` b="1"`},
		{run.Italic, ` i="1"`},
		{run.Underline, ` u="sng"`},
		{run.Strikethrough, ` strike="sngStrike"`},
	} {
		if attr.on {
			s.out.put(attr.attr)
		}
	}
	s.out.put(` dirty="0">`)
	c, ok := color{}, false
	if run.Color != nil {
		c, ok = resolveColor(*run.Color, s.theme)
	}
	if !ok && style.color != nil {
		c, ok = *style.color, true
	}
	if ok {
		s.out.put(solidFill(c, 1))
	}
	family := style.font
	if run.FontFamily != nil && strings.TrimSpace(*run.FontFamily) != "" {
		family = strings.TrimSpace(*run.FontFamily)
	}
	if family != "" {
		if generic, ok := genericFonts[family]; ok {
			family = generic
		}
		var face strings.Builder
		escape(&face, family)
		s.out.put(`<a:latin typeface="` + face.String() + `"/><a:cs typeface="` + face.String() + `"/>`)
	}
	s.out.put(`</` + tag + `>`)
}

// solidFill is c at its own alpha times opacity.
func solidFill(c color, opacity float64) string {
	alpha := int64(math.Round(c.alpha * opacity * 100_000))
	if alpha >= 100_000 {
		return `<a:solidFill><a:srgbClr val="` + c.rgb + `"/></a:solidFill>`
	}
	return fmt.Sprintf(`<a:solidFill><a:srgbClr val="%s"><a:alpha val="%d"/></a:srgbClr></a:solidFill>`, c.rgb, max(alpha, 0))
}

// opacityOf is an element's opacity, 1 when unset, within 0 to 1.
func opacityOf(v *float64) float64 {
	if v == nil {
		return 1
	}
	return math.Max(0, math.Min(1, *v))
}
