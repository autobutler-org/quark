package pptxutil_test

// cspell:ignore gridCol gridSpan hMerge lnB lnL lnR lnT srgb tbl tblPr tc tcPr tr vMerge xfrm

import (
	"bytes"
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

// tableRoundTripDeck is a table an import reads back exactly: every cell
// sets all four lines, every run its size, font and color, and nothing is
// merged, since an export writes each shared edge on both cells and draws
// the lines inside a merge as none.
const tableRoundTripDeck = `{
  "schemaVersion": 4,
  "title": "Tables",
  "size": {"width": 1920, "height": 1080},
  "slides": [
    {
      "id": "s1",
      "elements": [
        {"id": "t1", "type": "table", "frame": {"x": 100, "y": 200, "width": 600, "height": 160},
         "columns": [200, 400], "rows": [80, 80],
         "cells": [
           [
             {"paragraphs": [{"runs": [{"text": "Region", "bold": true, "fontSize": 36, "fontFamily": "Inter", "color": "#000000"}]}],
              "fill": "#3366FF",
              "borders": {"top": {"color": "#000000", "width": 2}, "right": {"color": "#000000", "width": 2},
                          "bottom": {"color": "#000000", "width": 2}, "left": {"color": "#000000", "width": 2}},
              "anchor": "middle"},
             {"paragraphs": [{"runs": [{"text": "Q3", "fontSize": 36, "fontFamily": "Inter", "color": "#FFCC00"}], "align": "center"}],
              "borders": {"top": {"color": "#000000", "width": 2}, "right": {"color": "#000000", "width": 2},
                          "bottom": {"color": "#000000", "width": 2}, "left": {"color": "#000000", "width": 2}}}
           ],
           [
             {"borders": {"top": {"color": "#000000", "width": 2}, "right": {"color": "#FF0000", "width": 4, "dash": "dash"},
                          "bottom": {"color": "#000000", "width": 2}, "left": {"color": "#000000", "width": 2}},
              "anchor": "bottom"},
             {"paragraphs": [{"runs": [{"text": "12", "fontSize": 36, "fontFamily": "Inter", "color": "#000000"}]},
                             {"runs": [{"text": "units", "italic": true, "fontSize": 24, "fontFamily": "Inter", "color": "#000000"}]}],
              "fill": "#EEEEEE",
              "borders": {"top": {"color": "#000000", "width": 2}, "right": {"color": "#000000", "width": 2},
                          "bottom": {"color": "#000000", "width": 2}, "left": {"color": "#FF0000", "width": 4, "dash": "dash"}}}
           ]
         ]}
      ]
    }
  ]
}`

// mergedTableDeck has a header row, banded rows, and a cell merged across
// two columns and two rows.
const mergedTableDeck = `{
  "schemaVersion": 4,
  "slides": [
    {
      "id": "s1",
      "elements": [
        {"id": "t1", "type": "table", "frame": {"x": 0, "y": 0, "width": 300, "height": 300},
         "columns": [100, 100, 100], "rows": [100, 100, 100],
         "headerRow": true, "bandedRows": true, "accent": "#224488",
         "cells": [
           [{"paragraphs": [{"runs": [{"text": "Head"}]}]}, {}, {"fill": "theme:accent2"}],
           [{"paragraphs": [{"runs": [{"text": "Big"}]}], "rowSpan": 2, "colSpan": 2}, {}, {}],
           [{}, {}, {}]
         ]}
      ]
    }
  ]
}`

func TestExportWritesATableAsAGraphicFrame(t *testing.T) {
	parts, result := export(t, mergedTableDeck, nil)
	if result.Slides != 1 {
		t.Fatalf("slides = %d", result.Slides)
	}
	slide := parts.part(t, "ppt/slides/slide1.xml")
	contains(t, "slide", slide,
		`<p:graphicFrame>`,
		`<p:xfrm><a:off x="0" y="0"/><a:ext cx="1905000" cy="1905000"/></p:xfrm>`,
		`<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl>`,
		`<a:tblPr firstRow="1" bandRow="1"/>`,
		`<a:gridCol w="635000"/>`,
		`<a:tr h="635000">`,
		// The anchor of the merge, the cell beside it, and the row under it.
		`<a:tc gridSpan="2" rowSpan="2">`,
		`<a:tc hMerge="1">`,
		`<a:tc gridSpan="2" vMerge="1">`,
		`<a:tc hMerge="1" vMerge="1">`,
		// Header fill and text in the theme's background; a role fill; the
		// band on the second body row, which the merge covers but for one cell.
		`<a:solidFill><a:srgbClr val="224488"/></a:solidFill></a:tcPr>`,
		`<a:t>Head</a:t>`,
		`<a:solidFill><a:srgbClr val="F1F3F6"/></a:solidFill></a:tcPr>`,
		`<a:solidFill><a:srgbClr val="00A3A3"/></a:solidFill></a:tcPr>`,
		`<a:tcPr marL="88900" marR="88900" marT="50800" marB="50800" anchor="t">`,
		// No line was set anywhere, so every edge is drawn as none.
		`<a:lnL w="0"><a:noFill/></a:lnL>`,
	)
	if strings.Count(slide, "<a:tc>")+strings.Count(slide, "<a:tc ") != 9 || strings.Count(slide, "<a:tr ") != 3 {
		t.Errorf("want 3 rows of 3 cells:\n%s", slide)
	}
	head := slide[strings.Index(slide, `<a:t>Head</a:t>`)-400 : strings.Index(slide, `<a:t>Head</a:t>`)]
	contains(t, "header run", head, `<a:srgbClr val="FFFFFF"/>`)
}

func TestExportLeavesOutATableTheEditorWouldRefuse(t *testing.T) {
	for name, table := range map[string]string{
		"no rows":     `"columns": [100], "rows": [], "cells": []`,
		"ragged":      `"columns": [100, 100], "rows": [100], "cells": [[{}]]`,
		"short grid":  `"columns": [100], "rows": [100, 100], "cells": [[{}]]`,
		"too many":    `"columns": [` + strings.Repeat("1,", 100) + `1], "rows": [1], "cells": []`,
		"unknown key": `"columns": [100], "rows": [100], "cells": [[{}]], "future": true`,
	} {
		deck := `{"schemaVersion": 4, "slides": [{"id": "s1", "elements": [
			{"id": "t", "type": "table", "frame": {"x": 0, "y": 0, "width": 100, "height": 100}, ` + table + `}]}]}`
		parts, _ := export(t, deck, nil)
		slide := parts.part(t, "ppt/slides/slide1.xml")
		if got := strings.Contains(slide, "<a:tbl>"); got != (name == "unknown key") {
			t.Errorf("%s: table written = %v", name, got)
		}
	}
}

func TestImportReadsBackATableTheExportWrote(t *testing.T) {
	var exported bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(tableRoundTripDeck), Out: &exported,
	}); err != nil {
		t.Fatal(err)
	}
	got, result := importPptx(t, exported.Bytes(), nil)
	if len(result.Warnings) != 0 {
		t.Errorf("warnings = %v", result.Warnings)
	}
	var want map[string]any
	if err := json.Unmarshal([]byte(tableRoundTripDeck), &want); err != nil {
		t.Fatal(err)
	}
	// An import writes schema version 1, which the editor migrates.
	want["schemaVersion"] = float64(1)
	if !reflect.DeepEqual(withoutIDs(got), withoutIDs(want)) {
		gotJSON, _ := json.MarshalIndent(withoutIDs(got), "", "  ")
		t.Errorf("round trip changed the table:\n%s", gotJSON)
	}
}

func TestImportReadsBackMergesAndTheHeader(t *testing.T) {
	var exported bytes.Buffer
	if _, err := pptxutil.ExportQslide(pptxutil.ExportQslideParams{
		Source: strings.NewReader(mergedTableDeck), Out: &exported,
	}); err != nil {
		t.Fatal(err)
	}
	got, _ := importPptx(t, exported.Bytes(), nil)
	table := elements(slides(got)[0])[0]
	if table["type"] != "table" || table["headerRow"] != true || table["bandedRows"] != true {
		t.Fatalf("table = %s", asJSON(table))
	}
	cells := table["cells"].([]any)
	anchor := cells[1].([]any)[0].(map[string]any)
	if anchor["rowSpan"] != float64(2) || anchor["colSpan"] != float64(2) {
		t.Errorf("anchor = %s", asJSON(anchor))
	}
	for _, covered := range []map[string]any{
		cells[1].([]any)[1].(map[string]any),
		cells[2].([]any)[0].(map[string]any),
		cells[2].([]any)[1].(map[string]any),
	} {
		if covered["rowSpan"] != nil || covered["colSpan"] != nil {
			t.Errorf("a covered cell spans: %s", asJSON(covered))
		}
	}
	// The fills the export drew come back as each cell's own.
	if got := cells[0].([]any)[0].(map[string]any)["fill"]; got != "#224488" {
		t.Errorf("header fill = %v", got)
	}
	if got := cells[0].([]any)[2].(map[string]any)["fill"]; got != "#00A3A3" {
		t.Errorf("role fill = %v", got)
	}
	if got := asJSON(table["frame"]); got != `{"height":300,"width":300,"x":0,"y":0}` {
		t.Errorf("frame = %s", got)
	}
}

// tableFrame is a slide's graphic frame holding a table of the given grid
// and rows.
func tableFrame(grid, rows string) string {
	return `<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="9" name="T"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>` +
		`<p:xfrm><a:off x="635000" y="635000"/><a:ext cx="1270000" cy="635000"/></p:xfrm>` +
		`<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl>` +
		`<a:tblPr firstRow="1" bandRow="1"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr>` +
		`<a:tblGrid>` + grid + `</a:tblGrid>` + rows + `</a:tbl></a:graphicData></a:graphic></p:graphicFrame>`
}

func TestImportReadsAPowerPointTable(t *testing.T) {
	cell := func(text string) string {
		return `<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="1800"/><a:t>` + text +
			`</a:t></a:r></a:p></a:txBody><a:tcPr anchor="ctr"/></a:tc>`
	}
	b := deck(tableFrame(
		`<a:gridCol w="635000"/><a:gridCol w="635000"/>`,
		// A row PowerPoint grew past the frame, and a row with a cell short.
		`<a:tr h="635000">`+cell("A")+cell("B")+`</a:tr><a:tr h="317500">`+cell("C")+`</a:tr>`,
	))
	doc, result := importPptx(t, b.zip(t), nil)
	if len(result.Warnings) != 0 {
		t.Errorf("warnings = %v", result.Warnings)
	}
	// Behind it, the master's own shape.
	all := elements(slides(doc)[0])
	table := all[len(all)-1]
	if got := asJSON(table["frame"]); got != `{"height":150,"width":200,"x":100,"y":100}` {
		t.Errorf("frame = %s", got)
	}
	if asJSON(table["columns"]) != `[100,100]` || asJSON(table["rows"]) != `[100,50]` {
		t.Errorf("columns = %s, rows = %s", asJSON(table["columns"]), asJSON(table["rows"]))
	}
	if table["headerRow"] != true || table["bandedRows"] != true {
		t.Errorf("the style's flags were lost: %s", asJSON(table))
	}
	cells := table["cells"].([]any)
	first := cells[0].([]any)[0].(map[string]any)
	if first["anchor"] != "middle" || !strings.Contains(asJSON(first["paragraphs"]), `"text":"A"`) {
		t.Errorf("first cell = %s", asJSON(first))
	}
	if missing := cells[1].([]any)[1]; asJSON(missing) != `{}` {
		t.Errorf("a missing cell = %s, want a blank one", asJSON(missing))
	}
}

func TestImportSkipsATablePastTheLimits(t *testing.T) {
	grid := strings.Repeat(`<a:gridCol w="6350"/>`, 101)
	b := deck(tableFrame(grid, `<a:tr h="6350"></a:tr>`))
	doc, result := importPptx(t, b.zip(t), nil)
	for _, el := range elements(slides(doc)[0]) {
		if el["type"] == "table" {
			t.Errorf("the table was imported: %s", asJSON(el))
		}
	}
	want := "Tables of more than 500 rows, 100 columns or 5000 cells are not imported."
	if len(result.Warnings) != 1 || result.Warnings[0].Message != want {
		t.Errorf("warnings = %v", result.Warnings)
	}
}
