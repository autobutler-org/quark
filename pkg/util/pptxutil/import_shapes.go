package pptxutil

// cspell:ignore autofit chartex clr descr dgm grp ph prst xfrm

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"path"
	"strconv"
	"strings"
)

// The defaults PowerPoint draws what a file leaves unset with.
const (
	// defaultLineEMU is an outline's width when neither it nor its style
	// sets one: ¾ pt.
	defaultLineEMU = 9525
	// defaultFontHundredths is a font size nothing sets, 18 pt.
	defaultFontHundredths = 1800
	// defaultRoundRectAdj is a rounded rectangle's corner, as a share of its
	// shorter side in 100,000ths, when it sets none.
	defaultRoundRectAdj = 16667
)

// The default text insets, in EMU: 0.1 in left and right, 0.05 in top and
// bottom.
var defaultInsets = [4]int64{91_440, 45_720, 91_440, 45_720}

// presetKinds maps a preset geometry to the shape kind it imports as; the
// inverse of shapeGeometry.
var presetKinds = func() map[string]string {
	kinds := make(map[string]string, len(shapeGeometry))
	for kind, prst := range shapeGeometry {
		kinds[prst] = kind
	}
	return kinds
}()

// linePresets are the geometries that import as a line, and whether the
// line is drawn straight in place of the path PowerPoint draws.
var linePresets = map[string]bool{
	"line":               false,
	"straightConnector1": false,
	"bentConnector2":     true,
	"bentConnector3":     true,
	"bentConnector4":     true,
	"bentConnector5":     true,
	"curvedConnector2":   true,
	"curvedConnector3":   true,
	"curvedConnector4":   true,
	"curvedConnector5":   true,
}

// dashes maps a preset dash to the stroke dash it imports as.
var dashes = map[string]string{
	"dash": "dash", "lgDash": "dash", "sysDash": "dash",
	"dot": "dot", "sysDot": "dot",
	"dashDot": "dashDot", "lgDashDot": "dashDot", "lgDashDotDot": "dashDot", "sysDashDot": "dashDot",
	"sysDashDotDot": "dashDot",
}

// styleLineEMU is the outline width of each theme line style a shape's style
// can reference, as PowerPoint's default theme sets them.
var styleLineEMU = map[string]int64{"1": 6350, "2": 12_700, "3": 19_050}

// pictureFormats maps a sniffed picture type to the extension it is stored
// under: the formats the editor shows.
var pictureFormats = map[string]string{
	"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/bmp": "bmp", "image/webp": "webp",
}

// transform maps a group's child coordinates onto the group's own box:
// local = (child - ch) * s, in EMU of the slide.
type transform struct {
	chX, chY float64
	sx, sy   float64
}

// identity is the slide's own coordinate space.
var identity = transform{sx: 1, sy: 1}

// frame converts a transform to a frame in slide units.
func (s *slideReader) frame(x *xXfrm, t transform) outFrame {
	return outFrame{
		X:        round((float64(x.Off.X) - t.chX) * t.sx / s.scale),
		Y:        round((float64(x.Off.Y) - t.chY) * t.sy / s.scale),
		Width:    round(math.Max(float64(x.Ext.CX), 0) * t.sx / s.scale),
		Height:   round(math.Max(float64(x.Ext.CY), 0) * t.sy / s.scale),
		Rotation: degrees(int64(x.Rot)),
	}
}

// degrees converts 60,000ths of a degree to degrees within one turn.
func degrees(rot int64) float64 {
	d := math.Mod(float64(rot)/60_000, 360)
	if d < 0 {
		d += 360
	}
	return round(d)
}

// convertChildren converts a shape tree's children, back to front. For a
// layout or master, template is set and placeholders are left out.
func (s *slideReader) convertChildren(items []xTreeItem, t transform, depth int, template bool) ([]outElement, error) {
	if depth > MaxGroupDepth {
		return nil, fmt.Errorf("%w: groups nest more than %d deep", ErrTooLarge, MaxGroupDepth)
	}
	out := []outElement{}
	for _, item := range items {
		var converted []outElement
		var err error
		switch {
		case item.Shape != nil:
			converted, err = s.convertShape(item.Shape, t, false, template)
		case item.Connector != nil:
			converted, err = s.convertShape(item.Connector, t, true, template)
		case item.Picture != nil:
			converted, err = s.convertPicture(item.Picture, t, template)
		case item.Group != nil:
			converted, err = s.convertGroup(item.Group, t, depth, template)
		case item.Frame != nil:
			s.warn(graphicFrameWarning(item.Frame.Data.URI))
		case item.Other == "contentPart":
			s.warn("Ink drawings are not imported.")
		}
		if err != nil {
			return nil, err
		}
		out = append(out, converted...)
	}
	return out, nil
}

// graphicFrameWarning names what a graphic frame held.
func graphicFrameWarning(uri string) string {
	switch {
	case strings.HasSuffix(uri, "/table"):
		return "Tables are not imported."
	case strings.HasSuffix(uri, "/chart") || strings.Contains(uri, "chartex"):
		return "Charts are not imported."
	case strings.HasSuffix(uri, "/diagram"):
		return "SmartArt graphics are not imported."
	}
	return "Embedded objects are not imported."
}

// convertGroup converts a group and its children into the group's local
// space. A group without a transform contributes its children in place.
func (s *slideReader) convertGroup(g *xGroup, t transform, depth int, template bool) ([]outElement, error) {
	if g.Props.Common.Hidden {
		return nil, nil
	}
	if g.Xfrm == nil {
		return s.convertChildren(g.Children, t, depth+1, template)
	}
	child := transform{sx: t.sx, sy: t.sy}
	if g.Xfrm.ChildOff != nil {
		child.chX, child.chY = float64(g.Xfrm.ChildOff.X), float64(g.Xfrm.ChildOff.Y)
	}
	if ext := g.Xfrm.ChildExt; ext != nil && ext.CX > 0 && ext.CY > 0 {
		child.sx *= float64(g.Xfrm.Ext.CX) / float64(ext.CX)
		child.sy *= float64(g.Xfrm.Ext.CY) / float64(ext.CY)
	}
	children, err := s.convertChildren(g.Children, child, depth+1, template)
	if err != nil || len(children) == 0 {
		return nil, err
	}
	if err := s.countElement(); err != nil {
		return nil, err
	}
	return []outElement{outGroup{ID: s.id(), Type: typeGroup, Frame: s.frame(g.Xfrm, t), Children: children}}, nil
}

// convertShape converts a shape or connector: a line, a preset shape, a
// text box, or a shape with a text box over it, which is how the editor
// draws text inside a shape.
func (s *slideReader) convertShape(sp *xShape, t transform, connector, template bool) ([]outElement, error) {
	nv := sp.nonVisual()
	ph := nv.App.Placeholder
	if bool(nv.Common.Hidden) || (template && ph != nil) {
		return nil, nil
	}
	var chain []*xShape
	if ph != nil {
		chain = s.placeholderChain(ph)
	}
	xfrm := sp.Props.Xfrm
	for _, inherited := range chain {
		if xfrm == nil {
			xfrm = inherited.Props.Xfrm
		}
	}
	if xfrm == nil {
		// Nothing says where it goes.
		return nil, nil
	}
	frame := s.frame(xfrm, t)

	prst := ""
	if sp.Props.Geometry != nil {
		prst = sp.Props.Geometry.Preset
	}
	if bent, ok := linePresets[prst]; ok || (connector && prst == "") {
		return s.convertLine(sp, frame, xfrm, bent)
	}

	fill := s.fill(sp.Props.xFill, styleRef(sp.Style, "fill"))
	stroke := s.stroke(sp.Props.Line, sp.Style)
	drawn := fill != "" || stroke != nil
	hasText := sp.Text != nil && visibleText(sp.Text)
	textBox := bool(nv.ShapeProps.TextBox) || ph != nil
	var out []outElement
	// A shape with neither fill nor outline is still a shape the editor can
	// select, unless it is only there to hold text.
	if drawn || (!textBox && !hasText) {
		shape, err := s.presetShape(sp, prst, frame, fill, stroke)
		if err != nil {
			return nil, err
		}
		out = append(out, shape)
	}
	// A placeholder with no text is only a prompt; an empty text box of the
	// slide's own is kept, as PowerPoint keeps it.
	if sp.Text != nil && (hasText || (textBox && ph == nil)) {
		if err := s.countElement(); err != nil {
			return nil, err
		}
		out = append(out, s.textBox(sp, chain, ph, frame, t))
	}
	return out, nil
}

// presetShape is the shape a geometry draws, a rectangle when the editor
// has no such kind.
func (s *slideReader) presetShape(sp *xShape, prst string, frame outFrame, fill string, stroke *outStroke) (outShape, error) {
	if err := s.countElement(); err != nil {
		return outShape{}, err
	}
	kind, ok := presetKinds[prst]
	switch {
	case sp.Props.Custom != nil:
		s.warn("Freeform shapes were drawn as rectangles.")
		kind = "rectangle"
	case prst == "":
		kind = "rectangle"
	case !ok:
		s.warn(fmt.Sprintf("Shapes of a kind the editor does not have (%s) were drawn as rectangles.", prst))
		kind = "rectangle"
	}
	shape := outShape{ID: s.id(), Type: typeShape, Frame: frame, Kind: kind, Fill: fill, Stroke: stroke}
	if kind == "roundedRectangle" {
		adj := float64(defaultRoundRectAdj)
		for _, gd := range sp.Props.Geometry.Guides {
			if v, ok := strings.CutPrefix(gd.Formula, "val "); gd.Name == "adj" && ok {
				if n, err := strconv.ParseFloat(strings.TrimSpace(v), 64); err == nil {
					adj = math.Max(0, math.Min(n, 50_000))
				}
			}
		}
		radius := round(adj / 100_000 * math.Min(frame.Width, frame.Height))
		shape.CornerRadius = &radius
	}
	return shape, nil
}

// convertLine converts a line or connector, drawn across its frame's
// diagonal; flipped when it runs bottom left to top right.
func (s *slideReader) convertLine(sp *xShape, frame outFrame, xfrm *xXfrm, bent bool) ([]outElement, error) {
	stroke := s.stroke(sp.Props.Line, sp.Style)
	if stroke == nil {
		return nil, nil
	}
	if err := s.countElement(); err != nil {
		return nil, err
	}
	if bent {
		s.warn("Bent and curved connectors were drawn as straight lines.")
	}
	line := outLine{
		ID: s.id(), Type: typeLine, Frame: frame, Stroke: *stroke,
		Flipped: bool(xfrm.FlipH) != bool(xfrm.FlipV),
	}
	if ln := sp.Props.Line; ln != nil {
		line.StartCap, line.EndCap = lineCap(ln.Head), lineCap(ln.Tail)
	}
	return []outElement{line}, nil
}

// lineCap is the cap a line end imports as.
func lineCap(end *xLineEnd) string {
	if end == nil || end.Type == "" || end.Type == "none" {
		return ""
	}
	return "arrow"
}

// convertPicture converts a picture, storing it the first time it is seen.
func (s *slideReader) convertPicture(p *xPicture, t transform, template bool) ([]outElement, error) {
	nv := p.NV
	ph := nv.App.Placeholder
	if bool(nv.Common.Hidden) || (template && ph != nil) {
		return nil, nil
	}
	if nv.App.Video != nil || nv.App.Audio != nil || nv.App.QuickTime != nil || nv.App.WavAudio != nil ||
		nv.App.AudioCD != nil {
		s.warn("Video and audio are not imported.")
		return nil, nil
	}
	xfrm := p.Props.Xfrm
	if xfrm == nil && ph != nil {
		for _, inherited := range s.placeholderChain(ph) {
			if xfrm == nil {
				xfrm = inherited.Props.Xfrm
			}
		}
	}
	if xfrm == nil {
		return nil, nil
	}
	ref, ok, err := s.picture(s.source, p.Fill)
	if err != nil || !ok {
		return nil, err
	}
	if err := s.countElement(); err != nil {
		return nil, err
	}
	fit := "fill"
	if c := p.Fill.Crop; c != nil && (c.L > 0 || c.T > 0 || c.R > 0 || c.B > 0) {
		fit = "cover"
	}
	return []outElement{outImage{
		ID: s.id(), Type: typeImage, Frame: s.frame(xfrm, t), Source: ref, AltText: nv.Common.Descr, Fit: fit,
	}}, nil
}

// picture stores the picture a blip fill shows and returns its reference.
// One that cannot be stored is reported and comes back not ok; only a
// failure to store it at all is an error.
func (s *slideReader) picture(src source, fill xBlipFill) (string, bool, error) {
	if fill.Blip == nil || fill.Blip.Embed == "" {
		if fill.Blip != nil && fill.Blip.Link != "" {
			s.warn("Linked pictures are not imported; only pictures saved in the file are.")
		}
		return "", false, nil
	}
	rel, ok := src.rels[fill.Blip.Embed]
	part, inside := resolveTarget(src.part, rel.Target)
	if !ok || !inside || !s.a.has(part) {
		s.warn("Some pictures were missing from the file.")
		return "", false, nil
	}
	key := strings.ToLower(part)
	if ref, seen := s.media[key]; seen {
		if ref == "" {
			s.warn(s.skipped[key])
		}
		return ref, ref != "", nil
	}
	ref, why, err := s.storePicture(part)
	if err != nil {
		return "", false, err
	}
	s.media[key] = ref
	if ref == "" {
		s.skipped[key] = why
		s.warn(why)
		return "", false, nil
	}
	s.result.Pictures++
	return ref, true, nil
}

// storePicture streams one media part to StoreMedia. It returns the stored
// reference, or why the picture was left out.
func (s *slideReader) storePicture(part string) (string, string, error) {
	if s.params.StoreMedia == nil {
		return "", "Pictures are not imported here.", nil
	}
	declared := int64(min(s.a.parts[strings.ToLower(part)].UncompressedSize64, math.MaxInt64))
	tooLarge := fmt.Sprintf("Pictures larger than %d MiB were left out.", MaxImageBytes>>20)
	if declared > MaxImageBytes {
		return "", tooLarge, nil
	}
	if s.mediaBytes+declared > MaxMediaBytes {
		return "", fmt.Sprintf("Pictures past the first %d MiB were left out.", MaxMediaBytes>>20), nil
	}
	rc, err := s.a.open(part, MaxImageBytes)
	if err != nil {
		return "", "", err
	}
	defer rc.Close()
	reader := rc.(*budgetReader)

	head := make([]byte, 512)
	n, err := io.ReadFull(rc, head)
	if err != nil && !errors.Is(err, io.EOF) && !errors.Is(err, io.ErrUnexpectedEOF) {
		return "", "", s.mediaReadError(err)
	}
	head = head[:n]
	ext, ok := pictureFormats[http.DetectContentType(head)]
	if !ok {
		format := strings.ToUpper(strings.TrimPrefix(path.Ext(part), "."))
		if format == "" {
			format = "unknown"
		}
		return "", fmt.Sprintf("Pictures in a format the editor cannot show (%s) were left out.", format), nil
	}

	ref, err := s.params.StoreMedia(mediaName(part, ext), io.MultiReader(bytes.NewReader(head), rc))
	s.mediaBytes += reader.read
	switch {
	case reader.pastBudget:
		return "", "", fmt.Errorf("%w: the package unpacks to more than %d bytes", ErrTooLarge, int64(MaxImportBytes))
	case reader.pastLimit:
		return "", tooLarge, nil
	case err != nil:
		return "", "", err
	}
	return ref, "", nil
}

// mediaReadError keeps a read past the budget [ErrTooLarge] and makes any
// other failure to unpack a picture the file's fault.
func (s *slideReader) mediaReadError(err error) error {
	if errors.Is(err, ErrTooLarge) {
		return err
	}
	return fmt.Errorf("%w: %v", ErrNotPptx, err)
}

// mediaName is the name a media part is stored under: its own stem, kept to
// characters every filesystem takes, and the extension of its content.
func mediaName(part, ext string) string {
	stem := strings.TrimSuffix(path.Base(part), path.Ext(part))
	var b strings.Builder
	for _, r := range stem {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
		if b.Len() >= 64 {
			break
		}
	}
	if b.Len() == 0 {
		b.WriteString("image")
	}
	return b.String() + "." + ext
}

// placeholderChain is what a slide's placeholder inherits from, nearest
// first: the layout's placeholder it fills, then the master's.
func (s *slideReader) placeholderChain(ph *xPlaceholder) []*xShape {
	var chain []*xShape
	match := ph
	if s.layout != nil {
		if sp := findPlaceholder(s.layout.part.Tree.Children, ph, true); sp != nil {
			chain = append(chain, sp)
			if layoutPh := sp.nonVisual().App.Placeholder; layoutPh != nil {
				match = layoutPh
			}
		}
	}
	if s.master != nil {
		if sp := findPlaceholder(s.master.part.Tree.Children, match, false); sp != nil {
			chain = append(chain, sp)
		}
	}
	return chain
}

// findPlaceholder finds the placeholder ph fills among a template's shapes:
// by index when byIndex and ph has one, else by type.
func findPlaceholder(items []xTreeItem, ph *xPlaceholder, byIndex bool) *xShape {
	if byIndex && ph.Idx != "" {
		for _, item := range items {
			if item.Shape != nil {
				if candidate := item.Shape.nonVisual().App.Placeholder; candidate != nil && candidate.Idx == ph.Idx {
					return item.Shape
				}
			}
		}
	}
	want := placeholderKind(ph.Type)
	for _, item := range items {
		if item.Shape != nil {
			if candidate := item.Shape.nonVisual().App.Placeholder; candidate != nil && placeholderKind(candidate.Type) == want {
				return item.Shape
			}
		}
	}
	return nil
}

// placeholderKind folds the placeholder types a master does not have onto
// the ones it does.
func placeholderKind(phType string) string {
	switch phType {
	case "", "subTitle", "obj":
		return "body"
	case "ctrTitle":
		return "title"
	}
	return phType
}

// visibleText reports whether a text body holds any text.
func visibleText(body *xTextBody) bool {
	for _, p := range body.Paragraphs {
		for _, run := range p.Runs {
			if strings.TrimSpace(run.Text) != "" {
				return true
			}
		}
	}
	return false
}

// styleRef is one of a shape style's references, or nil.
func styleRef(style *xShapeStyle, which string) *xStyleRef {
	if style == nil {
		return nil
	}
	switch which {
	case "fill":
		return &style.Fill
	case "line":
		return &style.Line
	}
	return &style.Font
}

// fill is a shape's fill as a hex color, "" for none. A fill the editor
// cannot draw is approximated in one color, with a warning. With no fill of
// its own, a shape takes its style's.
func (s *slideReader) fill(f xFill, ref *xStyleRef) string {
	switch {
	case f.NoFill != nil, f.Group != nil:
		return ""
	case f.Solid != nil:
		return s.hex(f.Solid)
	case f.Gradient != nil:
		s.warn("Gradient fills were drawn in their first color.")
		if len(f.Gradient.Stops) > 0 {
			return s.hex(&f.Gradient.Stops[0].xColorChoice)
		}
		return ""
	case f.Pattern != nil:
		s.warn("Pattern fills were drawn in one color.")
		return s.hex(f.Pattern.Foreground)
	case f.Picture != nil:
		s.warn("Picture fills of shapes are not imported.")
		return ""
	}
	if ref != nil && ref.Idx != "" && ref.Idx != "0" {
		return s.hex(&ref.xColorChoice)
	}
	return ""
}

// stroke is a shape's outline, nil for none. With no line color of its own,
// a shape takes its style's.
func (s *slideReader) stroke(ln *xLine, style *xShapeStyle) *outStroke {
	ref := styleRef(style, "line")
	hasRef := ref != nil && ref.Idx != "" && ref.Idx != "0"
	var color string
	switch {
	case ln != nil && ln.NoFill != nil:
		return nil
	case ln != nil && (ln.Solid != nil || ln.Gradient != nil || ln.Pattern != nil):
		color = s.fill(ln.xFill, nil)
	case hasRef:
		color = s.hex(&ref.xColorChoice)
	}
	if color == "" {
		return nil
	}
	width := int64(defaultLineEMU)
	if hasRef {
		if w, ok := styleLineEMU[ref.Idx]; ok {
			width = w
		}
	}
	stroke := &outStroke{Color: color}
	if ln != nil {
		if ln.Width != nil {
			if w, err := strconv.ParseInt(strings.TrimSpace(*ln.Width), 10, 64); err == nil && w >= 0 {
				width = w
			}
		}
		if ln.Dash != nil {
			stroke.Dash = dashes[ln.Dash.Val]
		}
	}
	stroke.Width = round(float64(width) / s.scale)
	return stroke
}

// background is a slide's background: its own, else its layout's, else its
// master's. An inherited plain white one is the editor's default, so none.
func (s *slideReader) background(own *xBackground, layout, master *templatePart) (*outBackground, error) {
	type candidate struct {
		bg  *xBackground
		src source
	}
	candidates := []candidate{{own, s.source}}
	if layout != nil {
		candidates = append(candidates, candidate{layout.part.Background, source{layout.name, layout.rels}})
	}
	if master != nil {
		candidates = append(candidates, candidate{master.part.Background, source{master.name, master.rels}})
	}
	for i, c := range candidates {
		if c.bg == nil {
			continue
		}
		bg := &outBackground{}
		switch {
		case c.bg.Props != nil && c.bg.Props.Picture != nil:
			ref, ok, err := s.picture(c.src, *c.bg.Props.Picture)
			if err != nil {
				return nil, err
			}
			if ok {
				bg.Image = ref
			}
		case c.bg.Props != nil:
			bg.Color = s.fill(c.bg.Props.xFill, nil)
		case c.bg.Ref != nil:
			bg.Color = s.hex(&c.bg.Ref.xColorChoice)
		}
		if *bg == (outBackground{}) || (i > 0 && bg.Image == "" && bg.Color == "#FFFFFF") {
			return nil, nil
		}
		return bg, nil
	}
	return nil, nil
}
