package pptxutil_test

// cspell:ignore barDir cat chartSpace numCache numRef plotArea ptCount strCache strRef tbl tx xfrm

import (
	"fmt"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// chartDeck has two charts on its first slide and one on its second: the
// sample bar chart quark_slides' tests use, a pie, and a chart past the
// editor's table limits.
func chartDeck(manyCategories int) string {
	categories := make([]string, manyCategories)
	values := make([]string, manyCategories)
	for i := range categories {
		categories[i] = fmt.Sprintf(`"c%d"`, i)
		values[i] = "1"
	}
	return `{
  "schemaVersion": 5,
  "title": "Charts",
  "size": {"width": 1920, "height": 1080},
  "slides": [
    {"id": "s1", "elements": [
      {"id": "chart", "type": "chart", "frame": {"x": 360, "y": 200, "width": 1200, "height": 700},
       "kind": "bar", "categories": ["Q1", "Q2", "Q3"],
       "series": [{"name": "Revenue", "values": [12, 30, 42]}, {"name": "Costs", "values": [8, 12.5, null]}],
       "colors": ["#224488"], "title": "Sales", "dataLabels": true},
      {"id": "pie", "type": "chart", "frame": {"x": 0, "y": 0, "width": 400, "height": 400},
       "kind": "pie", "categories": ["North", "South"], "series": [{"values": [3, 1]}, {"values": [9, 9]}]}
    ]},
    {"id": "s2", "elements": [
      {"id": "big", "type": "chart", "frame": {"x": 0, "y": 0, "width": 400, "height": 400},
       "kind": "line", "categories": [` + strings.Join(categories, ",") + `],
       "series": [{"name": "A", "values": [` + strings.Join(values, ",") + `]}]},
      {"id": "odd", "type": "chart", "frame": {"x": 0, "y": 0, "width": 40, "height": 40},
       "kind": "scatter", "series": [1, 2]}
    ]}
  ]
}`
}

func TestExportWritesAChartAsASummaryAndATable(t *testing.T) {
	p, result := export(t, chartDeck(600), nil)
	slide := p.part(t, "ppt/slides/slide1.xml")
	wellFormed(t, "slide1", slide)
	contains(t, "slide 1", slide,
		"Bar chart titled Sales, 2 series, 3 categories; highest value 42 in Q3",
		"Pie chart, 1 series, 2 categories; highest value 3 in North",
		`<p:grpSp>`, `<a:tbl>`, `firstRow="1"`,
		"<a:t>Revenue</a:t>", "<a:t>Costs</a:t>", "<a:t>12.5</a:t>", "<a:t>0</a:t>")
	// A pie's table holds the series it draws, its first.
	lacks(t, "slide 1", slide, "<a:t>9</a:t>")

	second := p.part(t, "ppt/slides/slide2.xml")
	wellFormed(t, "slide2", second)
	// Past the editor's table limits, the summary alone.
	contains(t, "slide 2", second, "Line chart, 1 series, 600 categories; highest value 1 in c0",
		"Chart, no data")
	lacks(t, "slide 2", second, "<a:tbl>")

	want := []pptxutil.ExportWarning{
		{Slide: 1, Message: "Charts were exported as a text summary and a table of their data."},
		{Slide: 2, Message: "Charts were exported as a text summary and a table of their data."},
	}
	if fmt.Sprint(result.Warnings) != fmt.Sprint(want) {
		t.Errorf("warnings = %v, want %v", result.Warnings, want)
	}
}

func TestImportReadsBackAChartTheExportWroteAsText(t *testing.T) {
	p, _ := export(t, chartDeck(3), nil)
	doc, result := importPptx(t, pptxBuilder(p).zip(t), nil)
	group := elements(slides(doc)[0])[0]
	if group["type"] != "group" {
		t.Fatalf("chart came back as %s", asJSON(group))
	}
	children := group["children"].([]any)
	summary := asJSON(children[0])
	if !strings.Contains(summary, "Bar chart titled Sales, 2 series, 3 categories; highest value 42 in Q3") {
		t.Errorf("summary = %s", summary)
	}
	table := children[1].(map[string]any)
	if table["type"] != "table" || !strings.Contains(asJSON(table["cells"]), `"text":"12.5"`) {
		t.Errorf("table = %s", asJSON(table))
	}
	if len(result.Warnings) != 0 {
		t.Errorf("warnings = %v", result.Warnings)
	}
}

// chartFrame is a graphic frame showing the chart part rId7 names.
const chartFrame = `<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="9" name="Chart"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>` +
	`<p:xfrm><a:off x="635000" y="635000"/><a:ext cx="3810000" cy="2540000"/></p:xfrm>` +
	`<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">` +
	`<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="rId7"/>` +
	`</a:graphicData></a:graphic></p:graphicFrame>`

// chartPart is a horizontal bar chart of two series over three categories,
// as PowerPoint caches it.
const chartPart = `<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" ` +
	`xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><c:chart>` +
	`<c:title><c:tx><c:rich><a:p><a:r><a:t>Head</a:t></a:r><a:r><a:t>count</a:t></a:r></a:p></c:rich></c:tx></c:title>` +
	`<c:plotArea><c:layout/><c:barChart><c:barDir val="bar"/>` +
	`<c:ser><c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>North</c:v></c:pt></c:strCache></c:strRef></c:tx>` +
	`<c:cat><c:strRef><c:strCache><c:ptCount val="3"/><c:pt idx="0"><c:v>Jan</c:v></c:pt>` +
	`<c:pt idx="1"><c:v>Feb</c:v></c:pt><c:pt idx="2"><c:v>Mar</c:v></c:pt></c:strCache></c:strRef></c:cat>` +
	`<c:val><c:numRef><c:numCache><c:ptCount val="3"/><c:pt idx="0"><c:v>4</c:v></c:pt>` +
	`<c:pt idx="2"><c:v>7.25</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>` +
	`<c:ser><c:tx><c:v>South</c:v></c:tx>` +
	`<c:val><c:numRef><c:numCache><c:ptCount val="3"/><c:pt idx="1"><c:v>9</c:v></c:pt>` +
	// An index far past the count is no reason to allocate for it.
	`<c:pt idx="2000000000"><c:v>1</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>` +
	`</c:barChart><c:catAx/><c:valAx/></c:plotArea></c:chart></c:chartSpace>`

func TestImportReadsAPowerPointChartAsASummaryAndATable(t *testing.T) {
	b := deck(chartFrame)
	b["ppt/slides/_rels/slide1.xml.rels"] = rels(
		[3]string{"rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"},
		[3]string{"rId7", "chart", "../charts/chart1.xml"},
	)
	b["ppt/charts/chart1.xml"] = chartPart
	doc, result := importPptx(t, b.zip(t), nil)
	all := elements(slides(doc)[0])
	group := all[len(all)-1]
	if got := asJSON(group["frame"]); got != `{"height":400,"width":600,"x":100,"y":100}` {
		t.Errorf("frame = %s", got)
	}
	children := group["children"].([]any)
	if summary := asJSON(children[0]); !strings.Contains(summary,
		"Horizontal bar chart titled Headcount, 2 series, 3 categories; highest value 9 in Feb") {
		t.Errorf("summary = %s", summary)
	}
	cells := asJSON(children[1].(map[string]any)["cells"])
	for _, text := range []string{"North", "South", "Jan", "Mar", "7.25"} {
		if !strings.Contains(cells, `"text":"`+text+`"`) {
			t.Errorf("cells lack %q: %s", text, cells)
		}
	}
	want := "Charts were imported as a text summary and a table of their data."
	if len(result.Warnings) != 1 || result.Warnings[0].Message != want {
		t.Errorf("warnings = %v", result.Warnings)
	}
}

func TestImportSkipsAChartWhosePartIsMissing(t *testing.T) {
	b := deck(chartFrame)
	doc, result := importPptx(t, b.zip(t), nil)
	for _, el := range elements(slides(doc)[0]) {
		if el["type"] == "group" {
			t.Errorf("a chart was imported: %s", asJSON(el))
		}
	}
	want := "Charts whose data could not be read were left out."
	if len(result.Warnings) != 1 || result.Warnings[0].Message != want {
		t.Errorf("warnings = %v", result.Warnings)
	}
}
