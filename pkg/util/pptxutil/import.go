package pptxutil

// cspell:ignore clr ph

import (
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// The relationship types an import follows, by their last path segment, which
// the transitional and strict schemas share.
const (
	relSlide       = "/slide"
	relSlideLayout = "/slideLayout"
	relSlideMaster = "/slideMaster"
	relTheme       = "/theme"
	relNotesSlide  = "/notesSlide"
	relImage       = "/image"
	relOfficeDoc   = "/officeDocument"
	relCoreProps   = "/core-properties"
)

// importer carries the state of one import across its slides.
type importer struct {
	a      *officezip.Package
	params ImportPptxParams
	// scale is EMU per slide unit; see the package doc.
	scale float64
	// defaultText is the presentation's default text style, which text
	// outside a placeholder takes.
	defaultText *xListStyle
	// templates caches each layout and master by part, read once.
	templates map[string]*templatePart
	// templateElements counts the XML elements the cached templates hold.
	templateElements int
	// media maps a picture part to the reference it was stored under, ""
	// when it was skipped, and skipped to why.
	media      map[string]string
	skipped    map[string]string
	mediaBytes int64
	elements   int
	nextID     int
	// leftOut and approximated count the shapes whose shadows were left out
	// or drawn without their scale or skew; templateShadows is the layout
	// and master shapes already counted.
	leftOut, approximated shadowTally
	templateShadows       map[string]bool
	result                ImportPptxResult
}

// shadowTally counts shapes whose shadows did not come across as drawn, a
// layout's or master's once however many slides show it: slides is the
// slides one was on, and onSlide whether the slide being read has one.
type shadowTally struct {
	shapes  int
	slides  []int
	onSlide bool
}

// startSlide starts counting a slide and returns the count to restore if
// the slide cannot be read.
func (t *shadowTally) startSlide() int {
	t.onSlide = false
	return t.shapes
}

// endSlide notes slide number when a shadow was counted on it.
func (t *shadowTally) endSlide(number int) {
	if t.onSlide {
		t.slides = append(t.slides, number)
	}
	t.onSlide = false
}

// warnings is message, for the whole deck's count, on every slide counted.
// The count is the whole deck's, so the summary lists every slide under one
// line.
func (t *shadowTally) warnings(message func(shapes int) string) []ImportWarning {
	var out []ImportWarning
	for _, number := range t.slides {
		out = append(out, ImportWarning{Slide: number, Message: message(t.shapes)})
	}
	return out
}

// shadowFate is what became of a shape's own shadow.
type shadowFate int

const (
	// shadowNone is a shape without a shadow.
	shadowNone shadowFate = iota
	// shadowDrawn is a shadow that came across as it is drawn.
	shadowDrawn
	// shadowApproximated is a drop shadow that came across without its
	// scale or skew, or beside an inner or preset shadow that did not.
	shadowApproximated
	// shadowLeftOut is a shadow the editor does not draw: an inner or preset
	// one, or one on an element that casts none.
	shadowLeftOut
)

// templatePart is a layout or master, read once and drawn behind every slide
// that uses it.
type templatePart struct {
	name string
	part xSlidePart
	rels map[string]partRel
	// master is the layout's master; nil for a master.
	master *templatePart
	theme  *theme
	// colorMap maps a color role (tx1, bg1, ...) to a theme color.
	colorMap map[string]string
}

// readPptx converts every slide in show order, writing each as it goes.
func readPptx(a *officezip.Package, params ImportPptxParams) (ImportPptxResult, error) {
	im := &importer{
		a:               a,
		params:          params,
		templates:       map[string]*templatePart{},
		media:           map[string]string{},
		skipped:         map[string]string{},
		templateShadows: map[string]bool{},
	}
	presPart, err := im.mainPart()
	if err != nil {
		return im.result, err
	}
	var pres xPresentation
	if err := decodeXML(a, presPart, &pres); err != nil {
		return im.result, err
	}
	presRels, err := im.rels(presPart)
	if err != nil {
		return im.result, err
	}
	im.defaultText = pres.DefaultTextStyle
	if len(pres.EmbeddedFonts) > 0 {
		var typefaces []string
		for _, f := range pres.EmbeddedFonts {
			if f.Typeface != "" && !slices.Contains(typefaces, f.Typeface) {
				typefaces = append(typefaces, f.Typeface)
			}
		}
		im.result.Warnings = append(im.result.Warnings, ImportWarning{Message: embeddedFontsWarning(typefaces)})
	}
	size := im.setSize(int64(pres.SlideSize.CX), int64(pres.SlideSize.CY))

	out := &qslideWriter{w: params.Out}
	if err := out.header(im.title(), size); err != nil {
		return im.result, err
	}
	if len(pres.SlideIDs) > MaxSlides {
		return im.result, fmt.Errorf("%w: the presentation holds more than %d slides", ErrTooLarge, MaxSlides)
	}
	for i, id := range pres.SlideIDs {
		number := i + 1
		rel, ok := presRels[id.RelID]
		var slide outSlide
		var warnings []string
		leftOut, approximated := im.leftOut.startSlide(), im.approximated.startSlide()
		if ok && rel.Part != "" && a.Has(rel.Part) {
			slide, warnings, err = im.readSlide(rel.Part)
		} else {
			err = fmt.Errorf("%w: slide %d", errMissingPart, number)
		}
		if err != nil {
			if errors.Is(err, ErrTooLarge) || !isFileFault(err) {
				return im.result, err
			}
			// A slide that cannot be read is the file's fault; the deck keeps
			// its place in the show as an empty slide.
			slide = outSlide{Elements: []outElement{}}
			warnings = []string{"This slide could not be read, so it was left empty."}
			im.leftOut.shapes, im.leftOut.onSlide = leftOut, false
			im.approximated.shapes, im.approximated.onSlide = approximated, false
		}
		im.leftOut.endSlide(number)
		im.approximated.endSlide(number)
		slide.ID = fmt.Sprintf("s%d", number)
		for _, w := range warnings {
			im.result.Warnings = append(im.result.Warnings, ImportWarning{Slide: number, Message: w})
		}
		if err := out.slide(slide); err != nil {
			return im.result, err
		}
		im.result.Slides++
	}
	im.result.Warnings = append(im.result.Warnings, im.leftOut.warnings(shadowsLeftOutWarning)...)
	im.result.Warnings = append(im.result.Warnings, im.approximated.warnings(shadowsApproximatedWarning)...)
	return im.result, out.close()
}

// shadowsLeftOutWarning says how many shapes' shadows were left out.
func shadowsLeftOutWarning(shapes int) string {
	if shapes == 1 {
		return "The shadow on 1 shape was left out."
	}
	return fmt.Sprintf("Shadows on %d shapes were left out.", shapes)
}

// shadowsApproximatedWarning says how many shapes' shadows were drawn
// without their scale or skew.
func shadowsApproximatedWarning(shapes int) string {
	if shapes == 1 {
		return "The shadow on 1 shape may look slightly different."
	}
	return fmt.Sprintf("Shadows on %d shapes may look slightly different.", shapes)
}

// embeddedFontsWarning says the fonts a package embeds were not used,
// naming their typefaces when it can.
func embeddedFontsWarning(typefaces []string) string {
	names := ""
	switch n := len(typefaces); {
	case n == 1:
		names = " (" + typefaces[0] + ")"
	case n > 1:
		names = " (" + strings.Join(typefaces[:n-1], ", ") + " and " + typefaces[n-1] + ")"
	}
	return "Embedded fonts" + names + " were not carried over, so text may look different."
}

// isFileFault reports whether err is the package's fault rather than the
// server's.
func isFileFault(err error) bool {
	return errors.Is(err, ErrNotPptx) || errors.Is(err, errMissingPart)
}

// mainPart is the presentation part the package relationships point at,
// ppt/presentation.xml when they point at none.
func (im *importer) mainPart() (string, error) {
	rels, err := im.rels("")
	if err != nil {
		return "", err
	}
	for _, rel := range rels {
		if strings.HasSuffix(rel.Type, relOfficeDoc) && rel.Part != "" && im.a.Has(rel.Part) {
			return rel.Part, nil
		}
	}
	if im.a.Has("ppt/presentation.xml") {
		return "ppt/presentation.xml", nil
	}
	return "", fmt.Errorf("%w: no presentation part", ErrNotPptx)
}

// partRel is one internal relationship whose target has already been resolved
// to a part name. Part is empty when the target does not stay inside the
// package.
type partRel struct {
	Type string
	Part string
}

// rels reads a part's relationships by id; a part without any has none. The
// package's own are those of the part "". External targets are dropped, and
// each internal target is resolved with officezip so one that climbs out of
// the package resolves to nothing.
func (im *importer) rels(part string) (map[string]partRel, error) {
	name := relsPath(part)
	byID := map[string]partRel{}
	if !im.a.Has(name) {
		return byID, nil
	}
	var rels xRels
	if err := decodeXML(im.a, name, &rels); err != nil {
		return nil, err
	}
	for _, rel := range rels.Rels {
		if strings.EqualFold(rel.TargetMode, "External") {
			continue
		}
		target, ok := officezip.ResolveTarget(part, rel.Target)
		if !ok {
			target = ""
		}
		byID[rel.ID] = partRel{Type: rel.Type, Part: target}
	}
	return byID, nil
}

// related is the first internal part of relType a part's relationships name.
// Ids order the choice when there are several, so it does not depend on map
// order. A target that did not resolve is not a part.
func related(rels map[string]partRel, relType string) (string, bool) {
	best := ""
	for id, rel := range rels {
		if strings.HasSuffix(rel.Type, relType) && (best == "" || id < best) {
			best = id
		}
	}
	if best == "" || rels[best].Part == "" {
		return "", false
	}
	return rels[best].Part, true
}

// title is the package's title, or the caller's fallback.
func (im *importer) title() string {
	rels, err := im.rels("")
	if err == nil {
		if part, ok := related(rels, relCoreProps); ok && im.a.Has(part) {
			var core xCore
			if decodeXML(im.a, part, &core) == nil && strings.TrimSpace(core.Title) != "" {
				return strings.TrimSpace(core.Title)
			}
		}
	}
	return im.params.Title
}

// setSize picks the slide units for a slide cx by cy EMU; see the package
// doc. A missing or nonsensical size is PowerPoint's 16:9 default.
func (im *importer) setSize(cx, cy int64) outSize {
	if cx < minSlideEMU || cy < minSlideEMU || cx > maxSlideEMU || cy > maxSlideEMU {
		cx, cy = slideWidthEMU, 6_858_000
	}
	aspect := float64(cx) / float64(cy)
	size := outSize{Width: 1920, Height: round(1920 / aspect)}
	switch {
	case math.Abs(aspect-16.0/9) < 0.01:
		size.Height = 1080
	case math.Abs(aspect-4.0/3) < 0.01:
		size = outSize{Width: 1024, Height: 768}
	}
	im.scale = float64(cx) / size.Width
	return size
}

// template reads a layout or master once.
func (im *importer) template(name string, master *templatePart) (*templatePart, error) {
	if t, ok := im.templates[name]; ok {
		return t, nil
	}
	t := &templatePart{name: name, master: master}
	elements, err := decodeXMLCounted(im.a, name, &t.part)
	if err != nil {
		return nil, err
	}
	im.templateElements += elements
	if im.templateElements > MaxTemplateElements {
		return nil, fmt.Errorf("%w: the layouts and masters hold more than %d XML elements", ErrTooLarge, MaxTemplateElements)
	}
	rels, err := im.rels(name)
	if err != nil {
		return nil, err
	}
	t.rels = rels
	if master == nil {
		t.colorMap = map[string]string{}
		if t.part.ColorMap != nil {
			for _, attr := range t.part.ColorMap.Attrs {
				t.colorMap[attr.Name.Local] = attr.Value
			}
		}
		t.theme = &theme{colors: map[string]string{}}
		if themePart, ok := related(rels, relTheme); ok && im.a.Has(themePart) {
			t.theme, err = im.readTheme(themePart)
			if err != nil {
				return nil, err
			}
		}
	} else {
		t.colorMap, t.theme = master.colorMap, master.theme
	}
	im.templates[name] = t
	return t, nil
}

// readSlide converts one slide part: the master's and layout's own shapes,
// then the slide's, then its background and notes.
func (im *importer) readSlide(name string) (outSlide, []string, error) {
	var part xSlidePart
	if err := decodeXML(im.a, name, &part); err != nil {
		return outSlide{}, nil, err
	}
	rels, err := im.rels(name)
	if err != nil {
		return outSlide{}, nil, err
	}
	s := &slideReader{importer: im, warned: map[string]bool{}}
	var layout, master *templatePart
	if layoutPart, ok := related(rels, relSlideLayout); ok && im.a.Has(layoutPart) {
		layoutRels, err := im.rels(layoutPart)
		if err != nil {
			return outSlide{}, nil, err
		}
		if masterPart, ok := related(layoutRels, relSlideMaster); ok && im.a.Has(masterPart) {
			if master, err = im.template(masterPart, nil); err != nil {
				return outSlide{}, nil, err
			}
		}
		if master != nil {
			if layout, err = im.template(layoutPart, master); err != nil {
				return outSlide{}, nil, err
			}
		}
	}
	s.layout, s.master = layout, master
	s.theme = &theme{colors: map[string]string{}}
	s.colorMap = map[string]string{}
	if master != nil {
		s.theme, s.colorMap = master.theme, master.colorMap
	}

	slide := outSlide{Elements: []outElement{}}
	if part.Timing != nil {
		s.warn("Animations are not imported.")
	}
	transition, mapped := readTransition(part)
	if !mapped {
		s.warn("This slide's transition has no match in the editor, so it was left out.")
	}
	slide.Transition = transition
	// The master's shapes show unless the layout or slide hides them, and the
	// layout's unless the slide does.
	if layout != nil && showsMasterShapes(part.ShowMasterShapes) {
		if showsMasterShapes(layout.part.ShowMasterShapes) {
			if err := s.addTemplateShapes(&slide, master); err != nil {
				return outSlide{}, nil, err
			}
		}
		if err := s.addTemplateShapes(&slide, layout); err != nil {
			return outSlide{}, nil, err
		}
	}
	s.source = source{part: name, rels: rels}
	children, err := s.convertChildren(part.Tree.Children, identity, 0, false)
	if err != nil {
		return outSlide{}, nil, err
	}
	slide.Elements = append(slide.Elements, children...)

	if slide.Background, err = s.background(part.Background, layout, master); err != nil {
		return outSlide{}, nil, err
	}
	if notesPart, ok := related(rels, relNotesSlide); ok && im.a.Has(notesPart) {
		slide.Notes = s.notes(notesPart)
	}
	return slide, s.warnings, nil
}

// showsMasterShapes reads a showMasterSp attribute, which defaults to true.
func showsMasterShapes(attr *string) bool {
	return attr == nil || (*attr != "0" && *attr != "false")
}

// addTemplateShapes adds a layout's or master's own shapes — not its
// placeholders, which are only the slide's templates — behind the slide's.
func (s *slideReader) addTemplateShapes(slide *outSlide, t *templatePart) error {
	if t == nil {
		return nil
	}
	s.source = source{part: t.name, rels: t.rels}
	children, err := s.convertChildren(t.part.Tree.Children, identity, 0, true)
	if err != nil {
		return err
	}
	slide.Elements = append(slide.Elements, children...)
	return nil
}

// slideReader converts one slide's shapes.
type slideReader struct {
	*importer
	layout, master *templatePart
	theme          *theme
	colorMap       map[string]string
	// source is the part whose shapes are being read, for its pictures.
	source   source
	warnings []string
	warned   map[string]bool
}

// source is a part and its relationships.
type source struct {
	part string
	rels map[string]partRel
}

// warn records a warning once per slide.
func (s *slideReader) warn(message string) {
	if !s.warned[message] {
		s.warned[message] = true
		s.warnings = append(s.warnings, message)
	}
}

// noteShadow counts a converted shape or picture whose shadow is left out or
// drawn only approximately; carried is whether its element casts the drop
// shadow. A layout's or master's shape counts once, however many slides
// show it.
func (s *slideReader) noteShadow(props xShapeProps, nv xNonVisual, template, carried bool) {
	var tally *shadowTally
	switch props.shadowFate(carried) {
	case shadowLeftOut:
		tally = &s.leftOut
	case shadowApproximated:
		tally = &s.approximated
	default:
		return
	}
	tally.onSlide = true
	if template {
		key := s.source.part + "#" + nv.Common.ID
		if s.templateShadows[key] {
			return
		}
		s.templateShadows[key] = true
	}
	tally.shapes++
}

// shadow is the shape's own drop shadow in slide units, scaled like a
// stroke's width, or nil. Its offset is the slide's: one that turns with a
// shape turned rotation degrees — rotWithShape, the default — is turned
// with it. A color that cannot be read is black, PowerPoint's own.
func (s *slideReader) shadow(props xShapeProps, rotation float64) *outShadow {
	if props.Effects == nil || props.Effects.Outer == nil {
		return nil
	}
	o := props.Effects.Outer
	c := s.hex(&o.xColorChoice)
	if c == "" {
		c = "#000000"
	}
	degrees := float64(o.Dir) / 60_000
	if o.RotWithShape == nil || bool(*o.RotWithShape) {
		degrees += rotation
	}
	angle := degrees * math.Pi / 180
	dist := float64(o.Dist) / s.scale
	return &outShadow{
		Color: c,
		X:     round(dist * math.Cos(angle)),
		Y:     round(dist * math.Sin(angle)),
		Blur:  round(math.Max(float64(o.BlurRad), 0) / s.scale),
	}
}

// id returns the next element id.
func (s *slideReader) id() string {
	s.nextID++
	return fmt.Sprintf("e%d", s.nextID)
}

// countElement charges one element against [MaxElements].
func (s *slideReader) countElement() error {
	s.elements++
	if s.elements > MaxElements {
		return fmt.Errorf("%w: the presentation holds more than %d elements", ErrTooLarge, MaxElements)
	}
	return nil
}

// notes is the text of a notes slide's body placeholder, a line per
// paragraph. A notes slide that cannot be read has none.
func (s *slideReader) notes(name string) string {
	var part xSlidePart
	if err := decodeXML(s.a, name, &part); err != nil {
		return ""
	}
	var lines []string
	var walk func(items []xTreeItem)
	walk = func(items []xTreeItem) {
		for _, item := range items {
			if item.Group != nil {
				walk(item.Group.Children)
			}
			if item.Shape == nil || item.Shape.Text == nil {
				continue
			}
			ph := item.Shape.nonVisual().App.Placeholder
			if ph == nil || ph.Type != "body" {
				continue
			}
			for _, p := range item.Shape.Text.Paragraphs {
				var line strings.Builder
				for _, run := range p.Runs {
					if run.Break {
						line.WriteString("\n")
					}
					line.WriteString(run.Text)
				}
				lines = append(lines, line.String())
			}
		}
	}
	walk(part.Tree.Children)
	return strings.TrimRight(strings.Join(lines, "\n"), "\n")
}
