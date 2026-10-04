package pptxutil

import (
	"archive/zip"
	"bufio"
	"compress/flate"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"strings"
)

// Slide size bounds and the width a slide is mapped onto, in EMU (914,400 to
// the inch). PowerPoint refuses a slide outside 1 in to 56 in.
const (
	slideWidthEMU = 12_192_000
	minSlideEMU   = 914_400
	maxSlideEMU   = 51_206_400
	// emuPerHundredthPoint converts EMU to a font size's unit, hundredths of
	// a point: 12,700 EMU to the point.
	emuPerHundredthPoint = 127
)

// writePptx streams the .qslide in src onto w as a presentation. Each slide is
// decoded whole and written — pictures, slide, notes — before the next is
// read; the parts that list every slide are written last.
func writePptx(w io.Writer, src io.Reader, openImage OpenImageFunc) (ExportQslideResult, error) {
	zw := zip.NewWriter(w)
	// Pictures are deflated too (see copyImage), and gain almost nothing from
	// a slower level.
	zw.RegisterCompressor(zip.Deflate, func(out io.Writer) (io.WriteCloser, error) {
		return flate.NewWriter(out, flate.BestSpeed)
	})
	e := &exporter{
		zw:        zw,
		openImage: openImage,
		media:     map[string]*mediaPart{},
		imageExts: map[string]bool{},
	}
	dec := json.NewDecoder(src)
	dec.UseNumber()
	header, err := walkQslide(dec, func(header qslideHeader, slide qslideSlide) error {
		if e.scale == 0 {
			e.setSize(header.size)
		}
		if len(e.notes) == MaxSlides {
			return fmt.Errorf("%w: the presentation holds more than %d slides", ErrTooLarge, MaxSlides)
		}
		return e.writeSlide(slide)
	})
	if err != nil {
		return e.result, err
	}
	if e.scale == 0 {
		e.setSize(header.size)
	}
	if err := e.writePackageParts(header.title); err != nil {
		return e.result, err
	}
	return e.result, e.zw.Close()
}

// setSize derives the EMU scale and slide size; see the package doc.
func (e *exporter) setSize(size qslideSize) {
	scale := slideWidthEMU / size.Width
	switch {
	case size.Height*scale < minSlideEMU:
		scale = minSlideEMU / size.Height
	case size.Height*scale > maxSlideEMU:
		scale = maxSlideEMU / size.Height
	}
	e.scale = scale
	e.cx = clampEMU(math.Round(size.Width*scale), minSlideEMU, maxSlideEMU)
	e.cy = clampEMU(math.Round(size.Height*scale), minSlideEMU, maxSlideEMU)
}

// writeSlide writes one slide's pictures, its part and relationships, and its
// notes slide when it has notes.
func (e *exporter) writeSlide(slide qslideSlide) error {
	index := len(e.notes) + 1
	hasNotes := strings.TrimSpace(slide.Notes) != ""
	e.notes = append(e.notes, hasNotes)

	// One zip entry is open at a time, so the pictures go in ahead of the
	// slide that shows them.
	if err := e.embedAll(slide); err != nil {
		return err
	}

	part, err := e.zw.Create(fmt.Sprintf("ppt/slides/slide%d.xml", index))
	if err != nil {
		return err
	}
	sw := &slideWriter{
		exporter: e,
		out:      partWriter{bufio.NewWriter(part)},
		nextID:   2,
		rels:     map[string]string{},
		// rId1 is the layout, and rId2 the notes slide when there is one.
		firstImageRel: 2,
	}
	if hasNotes {
		sw.firstImageRel = 3
	}
	if err := sw.writeSlidePart(slide); err != nil {
		return err
	}

	var rels strings.Builder
	rels.WriteString(xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">`)
	rels.WriteString(relationship(1, "slideLayout", "../slideLayouts/slideLayout1.xml"))
	if hasNotes {
		rels.WriteString(relationship(2, "notesSlide", fmt.Sprintf("../notesSlides/notesSlide%d.xml", index)))
	}
	for i, name := range sw.relOrder {
		rels.WriteString(relationship(sw.firstImageRel+i, "image", "../media/"+name))
	}
	rels.WriteString(`</Relationships>`)
	if err := writePart(e.zw, fmt.Sprintf("ppt/slides/_rels/slide%d.xml.rels", index), rels.String()); err != nil {
		return err
	}

	if hasNotes {
		if err := writePart(e.zw, fmt.Sprintf("ppt/notesSlides/notesSlide%d.xml", index), notesSlidePart(slide.Notes)); err != nil {
			return err
		}
		notesRels := xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">` +
			relationship(1, "notesMaster", "../notesMasters/notesMaster1.xml") +
			relationship(2, "slide", fmt.Sprintf("../slides/slide%d.xml", index)) +
			`</Relationships>`
		if err := writePart(e.zw, fmt.Sprintf("ppt/notesSlides/_rels/notesSlide%d.xml.rels", index), notesRels); err != nil {
			return err
		}
	}
	e.result.Slides++
	return nil
}

// emu converts a length in slide units to EMU.
func (e *exporter) emu(v float64) int64 {
	return clampEMU(math.Round(v*e.scale), -maxCoordinate, maxCoordinate)
}

// fontSize converts a font size in slide units to hundredths of a point,
// within what PowerPoint accepts (1 pt to 4,000 pt).
func (e *exporter) fontSize(units float64) int64 {
	return clampEMU(math.Round(units*e.scale/emuPerHundredthPoint), 100, 400_000)
}

// maxCoordinate is the largest coordinate OOXML stores.
const maxCoordinate = 27_273_042_316_900

func clampEMU(v float64, lo, hi int64) int64 {
	if math.IsNaN(v) {
		return lo
	}
	return int64(math.Max(float64(lo), math.Min(float64(hi), v)))
}

// writePart writes body as the part name.
func writePart(zw *zip.Writer, name, body string) error {
	f, err := zw.Create(name)
	if err != nil {
		return err
	}
	_, err = io.WriteString(f, body)
	return err
}

// relationship is one <Relationship> of type kind (an officeDocument
// relationship type's last segment) to target.
func relationship(id int, kind, target string) string {
	return fmt.Sprintf(`<Relationship Id="rId%d" Type="%s/%s" Target="%s"/>`, id, nsRelationships, kind, target)
}

// put writes s. A failure is kept by the bufio.Writer and reported by Flush.
func (w partWriter) put(s string) { _, _ = w.WriteString(s) }

// printf writes a formatted string, its failure kept for Flush as put's is.
func (w partWriter) printf(format string, args ...any) { _, _ = fmt.Fprintf(w.Writer, format, args...) }

// text writes s as XML character data or an attribute value. EscapeText
// escapes quotes too and replaces characters XML cannot carry.
func (w partWriter) text(s string) { escape(w, s) }
