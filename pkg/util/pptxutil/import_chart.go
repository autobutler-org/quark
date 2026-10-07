package pptxutil

// cspell:ignore barDir cat chartex chartSpace numCache numLit numRef plotArea ptCount strCache strLit strRef tx xfrm

import (
	"encoding/xml"
	"errors"
	"math"
	"strconv"
	"strings"
)

// chartURI is the graphic data a chart's graphic frame holds.
const chartURI = "http://schemas.openxmlformats.org/drawingml/2006/chart"

// maxChartPoints bounds the points read from one series' cache, whatever
// index a point claims.
const maxChartPoints = maxTableCells

// xChartSpace is a chart part: its title and the chart groups of its plot
// area, each a kind of chart with its series.
type xChartSpace struct {
	Chart struct {
		Title *struct {
			Texts []string `xml:"tx>rich>p>r>t"`
		} `xml:"title"`
		PlotArea struct {
			Groups []xChartGroup `xml:",any"`
		} `xml:"plotArea"`
	} `xml:"chart"`
}

// xChartGroup is one chart in a plot area — c:barChart, c:lineChart and the
// rest — or another child of the plot area, which has no series.
type xChartGroup struct {
	XMLName xml.Name
	BarDir  struct {
		Val string `xml:"val,attr"`
	} `xml:"barDir"`
	Series []xChartSeries `xml:"ser"`
}

// xChartSeries is a series as PowerPoint caches it: its name, its
// categories and its values.
type xChartSeries struct {
	Tx struct {
		Cache xChartCache `xml:"strRef>strCache"`
		V     string      `xml:"v"`
	} `xml:"tx"`
	Cat xChartData `xml:"cat"`
	Val xChartData `xml:"val"`
}

// xChartData is a series' categories or values, from a reference's cache
// or written in place.
type xChartData struct {
	StrCache *xChartCache `xml:"strRef>strCache"`
	NumCache *xChartCache `xml:"numRef>numCache"`
	StrLit   *xChartCache `xml:"strLit"`
	NumLit   *xChartCache `xml:"numLit"`
}

// xChartCache is a cache of points by index.
type xChartCache struct {
	Count struct {
		Val int `xml:"val,attr"`
	} `xml:"ptCount"`
	Points []struct {
		Idx int    `xml:"idx,attr"`
		V   string `xml:"v"`
	} `xml:"pt"`
}

// cache is whichever cache the data has.
func (d xChartData) cache() *xChartCache {
	for _, c := range []*xChartCache{d.StrCache, d.NumCache, d.StrLit, d.NumLit} {
		if c != nil {
			return c
		}
	}
	return nil
}

// texts is the cache's points as text, by index; missing points are empty.
func (c *xChartCache) texts() []string {
	if c == nil {
		return nil
	}
	n := c.Count.Val
	for _, p := range c.Points {
		n = max(n, p.Idx+1)
	}
	out := make([]string, min(max(n, 0), maxChartPoints))
	for _, p := range c.Points {
		if p.Idx >= 0 && p.Idx < len(out) {
			out[p.Idx] = p.V
		}
	}
	return out
}

// chartKinds maps a chart group to the editor's chart kind.
var chartKinds = map[string]string{
	"barChart": "bar", "bar3DChart": "bar",
	"lineChart": "line", "line3DChart": "line",
	"pieChart": "pie", "pie3DChart": "pie", "doughnutChart": "pie", "ofPieChart": "pie",
	"areaChart": "area", "area3DChart": "area",
}

// readChart reads the chart a chart part holds: the first chart group's kind
// and every group's series, the categories of the first series that has
// any. It reports false when there is no series to read.
func readChart(cs *xChartSpace) (chartData, bool) {
	var c chartData
	if cs.Chart.Title != nil {
		c.title = strings.Join(cs.Chart.Title.Texts, "")
	}
	var series []xChartSeries
	for _, g := range cs.Chart.PlotArea.Groups {
		if len(g.Series) == 0 || !strings.HasSuffix(g.XMLName.Local, "Chart") {
			continue
		}
		if c.kind == "" {
			c.kind = chartKinds[g.XMLName.Local]
			if c.kind == "bar" && g.BarDir.Val == "bar" {
				c.kind = "horizontalBar"
			}
		}
		series = append(series, g.Series...)
	}
	if len(series) == 0 {
		return c, false
	}
	for _, s := range series {
		if c.categories = s.Cat.cache().texts(); len(c.categories) > 0 {
			break
		}
	}
	if len(c.categories) == 0 {
		// No categories: number the points.
		for i := range len(series[0].Val.cache().texts()) {
			c.categories = append(c.categories, strconv.Itoa(i+1))
		}
	}
	for _, s := range series {
		name := s.Tx.V
		if texts := s.Tx.Cache.texts(); len(texts) > 0 {
			name = texts[0]
		}
		values := make([]float64, len(c.categories))
		for i, text := range s.Val.cache().texts() {
			if i >= len(values) {
				break
			}
			if v, err := strconv.ParseFloat(strings.TrimSpace(text), 64); err == nil && !math.IsInf(v, 0) && !math.IsNaN(v) {
				values[i] = v
			}
		}
		c.series = append(c.series, chartSeries{name: name, values: values})
	}
	return c, true
}

// convertChart brings a chart in as export writes one: a group of a text box
// summarizing it over a table of the data PowerPoint cached for it. A chart
// whose part is missing or unreadable is skipped with a warning.
func (s *slideReader) convertChart(f *xGraphicFrame, t transform, template bool) ([]outElement, error) {
	if bool(f.Props.Common.Hidden) || f.Xfrm == nil || (template && f.Props.App.Placeholder != nil) {
		return nil, nil
	}
	rel, ok := s.source.rels[f.Data.Chart.ID]
	part, inside := resolveTarget(s.source.part, rel.Target)
	if !ok || !inside || !s.a.has(part) {
		s.warn(graphicFrameWarning(chartURI))
		return nil, nil
	}
	var cs xChartSpace
	if err := s.a.decodeXML(part, &cs); err != nil {
		if errors.Is(err, ErrTooLarge) {
			return nil, err
		}
		s.warn(graphicFrameWarning(chartURI))
		return nil, nil
	}
	chart, ok := readChart(&cs)
	if !ok {
		s.warn(graphicFrameWarning(chartURI))
		return nil, nil
	}
	s.warn(chartImportWarning)

	frame := s.frame(f.Xfrm, t)
	summaryFrame, tableFrame, withTable := chart.layout(frame.Width, frame.Height)
	size := chartSummaryFontSize
	children := []outElement{outText{
		ID: s.id(), Type: typeText, Frame: outFrameOf(summaryFrame),
		Paragraphs: []outParagraph{{Runs: []outRun{{Text: chart.summary(), Bold: true, FontSize: &size}}}},
	}}
	if err := s.countElement(); err != nil {
		return nil, err
	}
	if withTable {
		table, err := s.chartTable(chart.grid(), tableFrame)
		if err != nil {
			return nil, err
		}
		children = append(children, table)
	}
	if err := s.countElement(); err != nil {
		return nil, err
	}
	return []outElement{outGroup{ID: s.id(), Type: typeGroup, Frame: frame, Children: children}}, nil
}

// chartTable is a table of grid in frame, as export's chartTable writes it
// but in literal colors, as an import writes every color.
func (s *slideReader) chartTable(grid [][]string, frame qslideFrame) (outTable, error) {
	el := chartTable(grid, frame)
	size := chartTableFontSize
	edge := &outStroke{Color: "#4B5563", Width: 2}
	out := outTable{
		ID: s.id(), Type: typeTable, Frame: outFrameOf(frame), HeaderRow: true,
		Columns: el.Columns, Rows: el.Rows, Cells: make([][]outCell, len(el.Cells)),
	}
	for r, row := range el.Cells {
		out.Cells[r] = make([]outCell, len(row))
		for c, cell := range row {
			if err := s.countElement(); err != nil {
				return outTable{}, err
			}
			out.Cells[r][c].Borders = &outBorders{Top: edge, Right: edge, Bottom: edge, Left: edge}
			if len(cell.Paragraphs) > 0 {
				out.Cells[r][c].Paragraphs = []outParagraph{{Runs: []outRun{{
					Text: cell.Paragraphs[0].Runs[0].Text, FontSize: &size,
				}}}}
			}
		}
	}
	return out, nil
}

// outFrameOf is a .qslide frame as an import writes it, kept to two
// decimals.
func outFrameOf(f qslideFrame) outFrame {
	return outFrame{X: round(f.X), Y: round(f.Y), Width: round(f.Width), Height: round(f.Height)}
}
