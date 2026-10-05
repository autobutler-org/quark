package pptxutil

import (
	"archive/zip"
	"bufio"
	"io"
)

// qslideSize is a presentation's slide size in slide units.
type qslideSize struct {
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// qslideSlide is one slide as .qslide stores it.
type qslideSlide struct {
	Background *qslideBackground `json:"background"`
	Elements   []qslideElement   `json:"elements"`
	Notes      string            `json:"notes"`
	// Transition is the slide's own, nil to follow the deck's default.
	Transition *qslideTransition `json:"transition"`
}

// qslideTransition is how a slide comes on: a kind (none, fade, push, wipe,
// zoom), the direction a push or wipe travels (left when left out), and a
// duration in milliseconds (500 when left out).
type qslideTransition struct {
	Kind      string   `json:"kind"`
	Direction string   `json:"direction"`
	Duration  *float64 `json:"duration"`
}

// qslideBackground is a slide's own background: a color, an image drawn to
// cover the slide over it, or both.
type qslideBackground struct {
	Color string `json:"color"`
	Image string `json:"image"`
}

// qslideFrame is an element's box in slide units, rotated clockwise about its
// center by Rotation degrees.
type qslideFrame struct {
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	Width    float64 `json:"width"`
	Height   float64 `json:"height"`
	Rotation float64 `json:"rotation"`
}

// qslideElement is any element; Type says which of the fields apply. An
// element of a type this writer does not know keeps only its Type, so a field
// a newer writer gave a different shape cannot fail the export.
type qslideElement struct {
	Type  string      `json:"type"`
	Frame qslideFrame `json:"frame"`

	// A text box.
	Paragraphs []qslideParagraph `json:"paragraphs"`
	Anchor     string            `json:"anchor"`
	AutoFit    string            `json:"autoFit"`
	// TextRole is the theme text style unset runs take: title, subtitle, or
	// body when left out.
	TextRole string `json:"textRole"`

	// A shape, and the stroke and opacity a line shares.
	Kind         string        `json:"kind"`
	Fill         string        `json:"fill"`
	Stroke       *qslideStroke `json:"stroke"`
	CornerRadius *float64      `json:"cornerRadius"`
	Opacity      *float64      `json:"opacity"`

	// A picture.
	Source  string `json:"source"`
	AltText string `json:"altText"`
	Fit     string `json:"fit"`

	// A line.
	Flipped  bool   `json:"flipped"`
	StartCap string `json:"startCap"`
	EndCap   string `json:"endCap"`

	// A group, its children in group-local frames.
	Children []qslideElement `json:"children"`

	// A table: column widths and row heights in slide units, its cells a
	// row at a time, whether its first row is a header and its body rows
	// banded, and the header's fill.
	Columns    []float64      `json:"columns"`
	Rows       []float64      `json:"rows"`
	Cells      [][]qslideCell `json:"cells"`
	HeaderRow  bool           `json:"headerRow"`
	BandedRows bool           `json:"bandedRows"`
	Accent     string         `json:"accent"`

	// A chart, whose Kind is bar, horizontalBar, line, pie or area: its
	// category labels (strings, or numbers a lenient writer left), its
	// series, and its title.
	Categories []any          `json:"categories"`
	Series     []qslideSeries `json:"series"`
	Title      string         `json:"title"`
}

// qslideSeries is one row of a chart's numbers; a null value is 0.
type qslideSeries struct {
	Name   string     `json:"name"`
	Values []*float64 `json:"values"`
}

// qslideCell is one table cell: rich text like a text box's, held to an
// anchor edge, a fill, the lines along its edges, and — on the anchor of a
// merged area — how many rows and columns it spans (1 when left out).
type qslideCell struct {
	Paragraphs []qslideParagraph `json:"paragraphs"`
	Fill       string            `json:"fill"`
	Anchor     string            `json:"anchor"`
	RowSpan    int               `json:"rowSpan"`
	ColSpan    int               `json:"colSpan"`
	Borders    qslideBorders     `json:"borders"`
}

// qslideBorders are a cell's lines, nil where a side has none.
type qslideBorders struct {
	Top    *qslideStroke `json:"top"`
	Right  *qslideStroke `json:"right"`
	Bottom *qslideStroke `json:"bottom"`
	Left   *qslideStroke `json:"left"`
}

// qslideStroke is an outline. Dash is any: a custom pattern a newer writer
// stores as an array draws solid, as it does in the editor.
type qslideStroke struct {
	Color *string  `json:"color"`
	Width *float64 `json:"width"`
	Dash  any      `json:"dash"`
}

// qslideParagraph is one paragraph of a text box.
type qslideParagraph struct {
	Runs        []qslideRun `json:"runs"`
	Align       string      `json:"align"`
	LineSpacing *float64    `json:"lineSpacing"`
	List        string      `json:"list"`
}

// qslideRun is a span of text sharing one style; a nil style inherits.
type qslideRun struct {
	Text          string   `json:"text"`
	Bold          bool     `json:"bold"`
	Italic        bool     `json:"italic"`
	Underline     bool     `json:"underline"`
	Strikethrough bool     `json:"strikethrough"`
	FontSize      *float64 `json:"fontSize"`
	FontFamily    *string  `json:"fontFamily"`
	Color         *string  `json:"color"`
}

// color is a parsed .qslide color: RRGGBB hex and an alpha from 0 to 1.
type color struct {
	rgb   string
	alpha float64
}

// mediaPart is one embedded picture.
type mediaPart struct {
	// name is its part name under ppt/media.
	name string
	// width and height are its pixel size, for fitting it to a frame.
	width, height int
}

// exporter carries the state of one export across its slides.
type exporter struct {
	zw        *zip.Writer
	openImage OpenImageFunc
	// scale is EMU per slide unit; see the package doc.
	scale float64
	// theme is the presentation's theme, nil for none.
	theme *deckTheme
	// transition is the deck's default transition, nil for none.
	transition *qslideTransition
	// cx and cy are the slide size in EMU.
	cx, cy int64
	// media maps a picture source to its part, nil when it could not be
	// embedded, so each source is opened once per export.
	media      map[string]*mediaPart
	mediaBytes int64
	// imageExts are the picture extensions embedded, for the content types.
	imageExts map[string]bool
	// notes lists, per slide written, whether it has a notes slide.
	notes    []bool
	elements int
	result   ExportQslideResult
	// chartWarned is the last slide number warned about a chart, so each
	// slide is warned once.
	chartWarned int
}

// slideWriter writes one slide's shape tree.
type slideWriter struct {
	*exporter
	out partWriter
	// nextID is the next shape id on this slide; 1 is the tree itself.
	nextID int
	// rels maps a picture part to its relationship id on this slide.
	rels map[string]string
	// relOrder lists the picture parts in rels in the order they were added.
	relOrder []string
	// firstImageRel is the number of the first relationship pictures take.
	firstImageRel int
}

// partWriter buffers one part. put and printf keep a write failure in the
// bufio.Writer for Flush to report.
type partWriter struct{ *bufio.Writer }

// cappedReader reads at most remaining bytes of r, and reports
// [ErrTooLarge] once a byte past them is there.
type cappedReader struct {
	r         io.Reader
	remaining int64
}
