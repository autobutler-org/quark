package pptxutil

// cspell:ignore clr ph

import (
	"errors"
	"fmt"
	"math"
	"strings"
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
	a      *pptxArchive
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
	result     ImportPptxResult
}

// templatePart is a layout or master, read once and drawn behind every slide
// that uses it.
type templatePart struct {
	name string
	part xSlidePart
	rels map[string]xRel
	// master is the layout's master; nil for a master.
	master *templatePart
	theme  *theme
	// colorMap maps a color role (tx1, bg1, ...) to a theme color.
	colorMap map[string]string
}

// readPptx converts every slide in show order, writing each as it goes.
func readPptx(a *pptxArchive, params ImportPptxParams) (ImportPptxResult, error) {
	im := &importer{
		a:         a,
		params:    params,
		templates: map[string]*templatePart{},
		media:     map[string]string{},
		skipped:   map[string]string{},
	}
	presPart, err := im.mainPart()
	if err != nil {
		return im.result, err
	}
	var pres xPresentation
	if err := a.decodeXML(presPart, &pres); err != nil {
		return im.result, err
	}
	presRels, err := im.rels(presPart)
	if err != nil {
		return im.result, err
	}
	im.defaultText = pres.DefaultTextStyle
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
		if target, inside := resolveTarget(presPart, rel.Target); ok && inside && a.has(target) {
			slide, warnings, err = im.readSlide(target)
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
		}
		slide.ID = fmt.Sprintf("s%d", number)
		for _, w := range warnings {
			im.result.Warnings = append(im.result.Warnings, ImportWarning{Slide: number, Message: w})
		}
		if err := out.slide(slide); err != nil {
			return im.result, err
		}
		im.result.Slides++
	}
	return im.result, out.close()
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
		if strings.HasSuffix(rel.Type, relOfficeDoc) {
			if target, ok := resolveTarget("", rel.Target); ok && im.a.has(target) {
				return target, nil
			}
		}
	}
	if im.a.has("ppt/presentation.xml") {
		return "ppt/presentation.xml", nil
	}
	return "", fmt.Errorf("%w: no presentation part", ErrNotPptx)
}

// rels reads a part's relationships by id; a part without any has none. The
// package's own are those of the part "".
func (im *importer) rels(part string) (map[string]xRel, error) {
	name := "_rels/.rels"
	if part != "" {
		name = relsPath(part)
	}
	byID := map[string]xRel{}
	if !im.a.has(name) {
		return byID, nil
	}
	var rels xRels
	if err := im.a.decodeXML(name, &rels); err != nil {
		return nil, err
	}
	for _, rel := range rels.Rels {
		if !strings.EqualFold(rel.TargetMode, "External") {
			byID[rel.ID] = rel
		}
	}
	return byID, nil
}

// related is the first internal part of relType a part's relationships name.
func related(source string, rels map[string]xRel, relType string) (string, bool) {
	// Ids order the choice when there are several, so it does not depend on
	// map order.
	best := ""
	for id, rel := range rels {
		if strings.HasSuffix(rel.Type, relType) && (best == "" || id < best) {
			best = id
		}
	}
	if best == "" {
		return "", false
	}
	return resolveTarget(source, rels[best].Target)
}

// title is the package's title, or the caller's fallback.
func (im *importer) title() string {
	rels, err := im.rels("")
	if err == nil {
		if part, ok := related("", rels, relCoreProps); ok && im.a.has(part) {
			var core xCore
			if im.a.decodeXML(part, &core) == nil && strings.TrimSpace(core.Title) != "" {
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
	elements, err := im.a.decodeXMLCounted(name, &t.part)
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
		if themePart, ok := related(name, rels, relTheme); ok && im.a.has(themePart) {
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
	if err := im.a.decodeXML(name, &part); err != nil {
		return outSlide{}, nil, err
	}
	rels, err := im.rels(name)
	if err != nil {
		return outSlide{}, nil, err
	}
	s := &slideReader{importer: im, warned: map[string]bool{}}
	var layout, master *templatePart
	if layoutPart, ok := related(name, rels, relSlideLayout); ok && im.a.has(layoutPart) {
		layoutRels, err := im.rels(layoutPart)
		if err != nil {
			return outSlide{}, nil, err
		}
		if masterPart, ok := related(layoutPart, layoutRels, relSlideMaster); ok && im.a.has(masterPart) {
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
	if part.Timing != nil || part.Transition != nil {
		s.warn("Animations and transitions are not imported.")
	}
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
	if notesPart, ok := related(name, rels, relNotesSlide); ok && im.a.has(notesPart) {
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
	rels map[string]xRel
}

// warn records a warning once per slide.
func (s *slideReader) warn(message string) {
	if !s.warned[message] {
		s.warned[message] = true
		s.warnings = append(s.warnings, message)
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
	if err := s.a.decodeXML(name, &part); err != nil {
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
