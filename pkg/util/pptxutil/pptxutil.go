// Package pptxutil converts between .qslide presentations and PowerPoint
// (.pptx) packages, using nothing but archive/zip and encoding/xml: it writes
// a .qslide out as a .pptx for export (#1172), and reads a .pptx back in as a
// .qslide for import (#1171).
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
// their alt text and fit; groups, nested; tables, with their column widths,
// row heights, cell text, fills, borders and merged cells; rotation;
// stacking order; slide backgrounds; and speaker notes. An element type this writer does not know is
// left out, as is a picture it cannot embed — see [ExportQslideParams].
//
// Export reads .qslide schema versions 1 to 4. A version 2 deck stores its
// theme: a role color (theme:accent1) is resolved against it, text a run does
// not style takes the size, font and color of its box's text role, a slide
// without a background shows the theme's, and the theme's ten color roles and
// heading and body fonts become the package theme's color and font schemes, so
// PowerPoint offers the deck's own palette. A version 1 theme naming a
// built-in theme by id is that theme, as the editor migrates it.
//
// Import reads the same features back, from any PowerPoint file rather than
// only this package's own: placeholders take their position and text style
// from their layout and master, theme colors resolve to the theme's RGB, and
// the master's and layout's own shapes are drawn behind each slide's. A
// table's header and banded-row flags come across, but not the table style
// it names: its cells keep only the fills and lines they set themselves. A
// table past quark_slides' limits — 500 rows, 100 columns, 5,000 cells — is
// skipped. What the editor has no model for — charts, SmartArt, embedded
// objects, video
// and audio, ink, animations and transitions — is skipped and named in the
// slide's warnings; see [ImportPptx]. An import writes schema version 1, every
// color literal and no theme, which the editor migrates as it opens the file.
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
// Import takes its units from the slide size: a 16:9 or 4:3 slide becomes the
// editor's 1920×1080 or 1024×768 preset, so a deck exported here comes back in
// the units it left in, and any other shape is 1920 units wide and as tall as
// its aspect makes it. Lengths, stroke widths and font sizes divide by the
// same EMU-per-unit factor, and are kept to two decimals.
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

// Import limits. A .pptx is user-supplied, and a zip says what it holds before
// it is read, so each limit is checked against what is actually read.
const (
	// MaxImportEntries bounds the entries of one package, checked against its
	// directory before the directory is read.
	MaxImportEntries = 20_000
	// MaxImportBytes bounds what a package unpacks to, every part together.
	MaxImportBytes = 2 << 30 // 2 GiB
	// MaxXMLPartBytes bounds one XML part unpacked: a slide, a layout, a
	// theme.
	MaxXMLPartBytes = 32 << 20 // 32 MiB
	// MaxXMLElements bounds the elements of one XML part, which is what a
	// decoded part costs in memory.
	MaxXMLElements = 250_000
	// MaxTemplateElements bounds the elements of every layout and master
	// together: they are read once and kept for the slides that use them.
	MaxTemplateElements = 1_000_000
	// MaxXMLDepth bounds how deeply a part's elements nest.
	MaxXMLDepth = 256
	// maxCentralDirectoryBytes bounds the zip directory archive/zip reads
	// whole before anything else.
	maxCentralDirectoryBytes = 16 << 20 // 16 MiB
)

var (
	// ErrNotPptx reports a source that is not a PowerPoint package, or one
	// whose entry names climb out of it. The caller's file is at fault, so
	// callers answer 400 for it.
	ErrNotPptx = errors.New("pptxutil: not a pptx")
	// ErrNotQslide reports a source that is not a .qslide presentation, or
	// one written by a newer schema than this writer reads. The file is at
	// fault, not the server, so callers answer 400 for it.
	ErrNotQslide = errors.New("pptxutil: not a qslide")
	// ErrTooLarge reports a presentation past one of the limits above. Also
	// the caller's file, and also a 400.
	ErrTooLarge = errors.New("pptxutil: presentation exceeds the size limits")
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

// StoreMediaFunc stores a picture an import found, under a name like
// image1.png whose extension matches its content, and returns the reference
// the .qslide names it by. It reads r to EOF; r fails with [ErrTooLarge] past
// [MaxImageBytes], and a picture that fails that way is skipped with a
// warning. Any other error fails the import.
type StoreMediaFunc func(name string, r io.Reader) (string, error)

// ImportPptxParams is one .pptx on its way to becoming a .qslide.
type ImportPptxParams struct {
	// Source is the package, read in place: a zip's directory is at its end.
	Source io.ReaderAt
	// Size is Source's length in bytes.
	Size int64
	// Out receives the .qslide JSON, a slide at a time.
	Out io.Writer
	// StoreMedia stores the pictures the slides show. Each is stored once,
	// however many slides show it. Nil skips every picture, with a warning.
	StoreMedia StoreMediaFunc
	// Title is the presentation's title when the package names none.
	Title string
}

// ImportPptxResult reports what the imported presentation came to.
type ImportPptxResult struct {
	// Slides is the number of slides written.
	Slides int
	// Pictures is the number of distinct pictures stored.
	Pictures int
	// Warnings lists what was left out or approximated, slide by slide.
	Warnings []ImportWarning
}

// ImportWarning is one thing an import left out or approximated.
type ImportWarning struct {
	// Slide is the slide's number in show order, from 1; 0 is the deck.
	Slide int
	// Message says what, in a sentence a user can read.
	Message string
}

// ImportPptx reads the .pptx in params.Source and writes the equivalent
// .qslide to params.Out, one slide per slide in show order.
//
// What the editor cannot show is skipped and reported in the result's
// warnings — a chart, an oversized table, an unknown shape drawn as a
// rectangle — and is
// never a failure. Errors wrap [ErrNotPptx] when the source is not a
// PowerPoint package and [ErrTooLarge] past the import limits; anything else
// is a read, write or StoreMedia failure. Out may hold part of a .qslide when
// an error is returned.
func ImportPptx(params ImportPptxParams) (ImportPptxResult, error) {
	if params.Source == nil || params.Out == nil {
		return ImportPptxResult{}, errors.New("pptxutil: Source and Out are required")
	}
	archive, err := openArchive(params.Source, params.Size)
	if err != nil {
		return ImportPptxResult{}, err
	}
	return readPptx(archive, params)
}
