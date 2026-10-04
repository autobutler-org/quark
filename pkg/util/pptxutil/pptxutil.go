// Package pptxutil writes a .qslide presentation out as a PowerPoint (.pptx)
// package for export (#1172), using nothing but archive/zip and XML text.
//
// A .pptx is a zip of PresentationML parts: the content types, the package and
// presentation relationships, docProps, ppt/presentation.xml with the slide
// size, one blank slide master and layout with their theme, one
// ppt/slides/slideN.xml per slide, a notes master and one notesSlideN.xml per
// slide with speaker notes, and the pictures under ppt/media.
//
// What carries across: rectangles, rounded rectangles, ellipses, triangles,
// diamonds, right arrows and stars with their fill, outline (color, width,
// dash) and opacity; lines and arrows; text boxes with their runs (bold,
// italic, underline, strikethrough, size, font, color), alignment, line
// spacing, bullets and numbering, vertical anchor and auto-fit; pictures with
// their alt text and fit; groups, nested; rotation; stacking order; slide
// backgrounds; and speaker notes. An element type this writer does not know is
// left out, as is a picture it cannot embed — see [ExportQslideParams].
//
// # Units
//
// A slide is laid out in abstract slide units (1920×1080 for 16:9). The
// package maps the slide's width onto PowerPoint's widescreen width,
// 12,192,000 EMU (13⅓ in), so one unit of a 1920-wide slide is 6,350 EMU —
// half a point — and every length, stroke width and font size is scaled by the
// same factor: a 72-unit heading on a 1920-wide slide is 36 pt. Only when that
// would make the slide's height fall outside what PowerPoint accepts
// (1 in to 56 in) is the scale taken from the height instead.
//
// # Streaming
//
// The .qslide is decoded one slide at a time, and each slide's pictures, part
// and notes are written to the zip before the next slide is read. A picture is
// copied into the archive straight from the reader it is opened with; only its
// header is held, to learn its format and size. The parts that list every
// slide are written last.
package pptxutil

import (
	"errors"
	"io"
)

// Export limits. A presentation is user-supplied, so each is checked against
// what is actually read.
const (
	// MaxQslideBytes bounds the .qslide an export reads. Slides are decoded one
	// at a time, so this caps what a single oversized slide can cost.
	MaxQslideBytes = 64 << 20 // 64 MiB
	// MaxSlides is the number of slides one export writes.
	MaxSlides = 5_000
	// MaxElements bounds the elements of the whole deck, grouped ones
	// included.
	MaxElements = 200_000
	// MaxGroupDepth bounds how deeply groups nest.
	MaxGroupDepth = 32
	// MaxImageBytes is the largest picture embedded. A larger one is left out
	// and its frame drawn as a placeholder.
	MaxImageBytes = 100 << 20 // 100 MiB
	// MaxMediaBytes bounds the pictures of one export together; past it, the
	// rest are placeholders.
	MaxMediaBytes = 1 << 30 // 1 GiB
)

var (
	// ErrNotQslide reports a source that is not a .qslide presentation, or
	// one written by a newer schema than this writer reads. The file is at
	// fault, not the server, so callers answer 400 for it.
	ErrNotQslide = errors.New("pptxutil: not a qslide")
	// ErrTooLarge reports a presentation past one of the limits above. Also
	// the caller's file, and also a 400.
	ErrTooLarge = errors.New("pptxutil: presentation exceeds export limits")
)

// OpenImageFunc opens the picture a slide names by source — the reference an
// image element or slide background stores — and reports its size in bytes.
// The caller closes the reader.
type OpenImageFunc func(source string) (io.ReadCloser, int64, error)

// ExportQslideParams is one .qslide on its way to becoming a .pptx.
type ExportQslideParams struct {
	// Source is the .qslide JSON. It is read once, front to back.
	Source io.Reader
	// Out receives the .pptx package, written as each slide is read. A zip is
	// written front to back, so this is a plain stream.
	Out io.Writer
	// OpenImage resolves pictures. A picture it cannot open — or that is not
	// a PNG, JPEG, GIF or BMP, or is past [MaxImageBytes] — is drawn as a
	// gray placeholder carrying its alt text, so the slide keeps its layout.
	// Nil leaves every picture a placeholder.
	OpenImage OpenImageFunc
}

// ExportQslideResult reports what the exported presentation came to.
type ExportQslideResult struct {
	// Slides is the number of slides written.
	Slides int
	// Pictures is the number of distinct pictures embedded.
	Pictures int
	// MissingPictures is the number of distinct picture sources left as
	// placeholders.
	MissingPictures int
}

// ExportQslide reads the .qslide in params.Source and writes the equivalent
// presentation to params.Out, one slide per slide, in show order.
//
// Only one slide is held in memory at a time. Errors wrap [ErrNotQslide] when
// the source is not a .qslide and [ErrTooLarge] past the export limits;
// anything else is a read or write failure.
func ExportQslide(params ExportQslideParams) (ExportQslideResult, error) {
	if params.Source == nil || params.Out == nil {
		return ExportQslideResult{}, errors.New("pptxutil: Source and Out are required")
	}
	return writePptx(params.Out, &cappedReader{r: params.Source, remaining: MaxQslideBytes}, params.OpenImage)
}
