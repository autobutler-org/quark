package pptxutil

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

// A chart crosses between .qslide and .pptx as text: a summary and a table of
// its data. A native chart part needs an embedded workbook to be editable in
// PowerPoint, which is more than a slide converter should write; the summary
// and the table keep what the chart says.

// The messages a slide with a chart is warned with.
const (
	chartExportWarning = "Charts were exported as a text summary and a table of their data."
	chartImportWarning = "Charts were imported as a text summary and a table of their data."
)

// The size of the text a chart's summary and table are set in, in slide
// units on a 1920-wide slide: 12 pt and 10 pt.
const (
	chartSummaryFontSize = 24.0
	chartTableFontSize   = 20.0
)

// chartData is a chart's kind, title and numbers, read from a .qslide chart
// or a PowerPoint chart part.
type chartData struct {
	// kind is a quark_slides ChartKind name: bar, horizontalBar, line, pie
	// or area; anything else reads as a chart of no particular kind.
	kind       string
	title      string
	categories []string
	series     []chartSeries
}

// chartSeries is one named row of a chart's numbers.
type chartSeries struct {
	name   string
	values []float64
}

// chartFromQslide reads a .qslide chart element, each series fitted to the
// categories as ChartData fits it.
func chartFromQslide(el qslideElement) chartData {
	c := chartData{kind: el.Kind, title: el.Title}
	for _, cat := range el.Categories {
		switch v := cat.(type) {
		case string:
			c.categories = append(c.categories, v)
		case float64:
			c.categories = append(c.categories, strconv.FormatFloat(v, 'f', -1, 64))
		default:
			c.categories = append(c.categories, "")
		}
	}
	for _, s := range el.Series {
		values := make([]float64, len(c.categories))
		for i := range min(len(values), len(s.Values)) {
			if v := s.Values[i]; v != nil && !math.IsInf(*v, 0) && !math.IsNaN(*v) {
				values[i] = *v
			}
		}
		c.series = append(c.series, chartSeries{name: s.Name, values: values})
	}
	return c
}

// kindName is the English name of the chart's kind, as quark_slides'
// chartKindName has it.
func (c chartData) kindName() string {
	switch c.kind {
	case "bar":
		return "Bar chart"
	case "horizontalBar":
		return "Horizontal bar chart"
	case "line":
		return "Line chart"
	case "pie":
		return "Pie chart"
	case "area":
		return "Area chart"
	}
	return "Chart"
}

// drawn is the series the chart draws: a pie draws its first only.
func (c chartData) drawn() []chartSeries {
	if c.kind == "pie" && len(c.series) > 1 {
		return c.series[:1]
	}
	return c.series
}

// summary describes the chart as quark_slides' defaultSlideChartSummary
// does: "Bar chart titled Sales, 3 series, 5 categories; highest value 42
// in Q3".
func (c chartData) summary() string {
	named := c.kindName()
	if title := strings.TrimSpace(c.title); title != "" {
		named += " titled " + title
	}
	series := c.drawn()
	if len(series) == 0 || len(c.categories) == 0 {
		return named + ", no data"
	}
	bestS, bestC := 0, 0
	for s, one := range series {
		for i, v := range one.values {
			if v > series[bestS].values[bestC] {
				bestS, bestC = s, i
			}
		}
	}
	out := fmt.Sprintf("%s, %s, %s; highest value %s", named,
		count(len(series), "series", "series"),
		count(len(c.categories), "category", "categories"),
		formatChartValue(series[bestS].values[bestC]))
	if category := strings.TrimSpace(c.categories[bestC]); category != "" {
		out += " in " + category
	}
	return out
}

// count is n and the noun, singular or plural.
func count(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}

// grid is the chart's data as text, as ChartData.toGrid lays it out: series
// names across the top, categories down the side.
func (c chartData) grid() [][]string {
	series := c.drawn()
	header := []string{""}
	for _, s := range series {
		header = append(header, s.name)
	}
	rows := [][]string{header}
	for i, category := range c.categories {
		row := []string{category}
		for _, s := range series {
			row = append(row, formatChartValue(s.values[i]))
		}
		rows = append(rows, row)
	}
	return rows
}

// formatChartValue writes a value as quark_slides' formatChartValue does:
// whole numbers without a fraction, others to at most two decimals.
func formatChartValue(v float64) string {
	if v == math.Round(v) && math.Abs(v) < 1e15 {
		return strconv.FormatInt(int64(v), 10)
	}
	text := strings.TrimRight(strconv.FormatFloat(v, 'f', 2, 64), "0")
	text = strings.TrimSuffix(text, ".")
	if text == "-0" {
		return "0"
	}
	return text
}

// chartLayout splits a w × h chart box between the summary, along the top,
// and the table of data under it, as local frames; the table is left out
// (ok false) when the data is past the editor's table limits or there is
// none.
func (c chartData) layout(w, h float64) (summary qslideFrame, table qslideFrame, ok bool) {
	grid := c.grid()
	rows, cols := len(grid), len(grid[0])
	ok = rows > 1 && rows <= maxTableRows && cols <= maxTableColumns && rows*cols <= maxTableCells
	summaryHeight := h
	if ok {
		summaryHeight = math.Min(h*0.3, chartSummaryFontSize*4)
	}
	summary = qslideFrame{Width: w, Height: summaryHeight}
	table = qslideFrame{Y: summaryHeight, Width: w, Height: math.Max(h-summaryHeight, 1)}
	return summary, table, ok
}

// writeChart writes a chart as a group of its summary over a table of its
// data, and warns the slide.
func (s *slideWriter) writeChart(el qslideElement) {
	chart := chartFromQslide(el)
	if slide := len(s.notes); s.chartWarned != slide {
		s.chartWarned = slide
		s.result.Warnings = append(s.result.Warnings, ExportWarning{Slide: slide, Message: chartExportWarning})
	}
	summaryFrame, tableFrame, withTable := chart.layout(el.Frame.Width, el.Frame.Height)
	summarySize := chartSummaryFontSize
	group := qslideElement{Type: typeGroup, Frame: el.Frame, Children: []qslideElement{{
		Type:  typeText,
		Frame: summaryFrame,
		Paragraphs: []qslideParagraph{{Runs: []qslideRun{{
			Text: chart.summary(), Bold: true, FontSize: &summarySize,
		}}}},
	}}}
	if withTable {
		group.Children = append(group.Children, chartTable(chart.grid(), tableFrame))
	}
	s.writeGroup(group)
}

// chartTable is a table of grid in frame: a header row, every edge drawn as
// a new table in the editor draws it.
func chartTable(grid [][]string, frame qslideFrame) qslideElement {
	rows, cols := len(grid), len(grid[0])
	size := chartTableFontSize
	color, width := "theme:text2", 2.0
	edge := &qslideStroke{Color: &color, Width: &width}
	el := qslideElement{
		Type: typeTable, Frame: frame, HeaderRow: true,
		Columns: make([]float64, cols), Rows: make([]float64, rows), Cells: make([][]qslideCell, rows),
	}
	for c := range cols {
		el.Columns[c] = frame.Width / float64(cols)
	}
	for r, line := range grid {
		el.Rows[r] = frame.Height / float64(rows)
		el.Cells[r] = make([]qslideCell, cols)
		for c := range cols {
			cell := qslideCell{Borders: qslideBorders{Top: edge, Right: edge, Bottom: edge, Left: edge}}
			if c < len(line) && line[c] != "" {
				cell.Paragraphs = []qslideParagraph{{Runs: []qslideRun{{Text: line[c], FontSize: &size}}}}
			}
			el.Cells[r][c] = cell
		}
	}
	return el
}
