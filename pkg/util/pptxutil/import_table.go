package pptxutil

// cspell:ignore gridSpan hMerge tbl tc vMerge xfrm

import (
	"fmt"
	"math"
)

// outTable is a table, in the order TableElement writes its fields: its
// frame the sum of its columns and rows, and a cell for every row and
// column.
type outTable struct {
	ID         string    `json:"id"`
	Type       string    `json:"type"`
	Frame      outFrame  `json:"frame"`
	Columns    []float64 `json:"columns"`
	Rows       []float64 `json:"rows"`
	HeaderRow  bool      `json:"headerRow,omitempty"`
	BandedRows bool      `json:"bandedRows,omitempty"`
	// Accent is the header's fill; an import leaves it to the editor's
	// default and writes each cell's fill instead.
	Accent string      `json:"accent,omitempty"`
	Cells  [][]outCell `json:"cells"`
}

// outCell is one table cell, in the order SlideTableCell writes its fields;
// a blank cell is {}. A span of 1 is left out.
type outCell struct {
	Paragraphs []outParagraph `json:"paragraphs,omitempty"`
	Fill       string         `json:"fill,omitempty"`
	Borders    *outBorders    `json:"borders,omitempty"`
	Anchor     string         `json:"anchor,omitempty"`
	RowSpan    int            `json:"rowSpan,omitempty"`
	ColSpan    int            `json:"colSpan,omitempty"`
}

// outBorders are a cell's lines; a side without one is left out.
type outBorders struct {
	Top    *outStroke `json:"top,omitempty"`
	Right  *outStroke `json:"right,omitempty"`
	Bottom *outStroke `json:"bottom,omitempty"`
	Left   *outStroke `json:"left,omitempty"`
}

// convertGraphicFrame converts a table, and skips — with a warning — any
// other graphic frame: a chart, SmartArt, an embedded object.
func (s *slideReader) convertGraphicFrame(f *xGraphicFrame, t transform, template bool) ([]outElement, error) {
	if f.Data.URI != tableURI || f.Data.Table == nil {
		s.warn(graphicFrameWarning(f.Data.URI))
		return nil, nil
	}
	if bool(f.Props.Common.Hidden) || f.Xfrm == nil || (template && f.Props.App.Placeholder != nil) {
		return nil, nil
	}
	tbl := f.Data.Table
	rows, cols := len(tbl.Rows), len(tbl.Grid)
	if rows == 0 || cols == 0 {
		return nil, nil
	}
	if rows > maxTableRows || cols > maxTableColumns || rows*cols > maxTableCells {
		s.warn(fmt.Sprintf("Tables of more than %d rows, %d columns or %d cells are not imported.",
			maxTableRows, maxTableColumns, maxTableCells))
		return nil, nil
	}
	// Each cell is drawn as a shape is, so the deck's budget pays for it.
	for range rows * cols {
		if err := s.countElement(); err != nil {
			return nil, err
		}
	}

	out := outTable{
		ID: s.id(), Type: typeTable, Frame: s.frame(f.Xfrm, t),
		Columns: make([]float64, cols), Rows: make([]float64, rows), Cells: make([][]outCell, rows),
		HeaderRow: bool(tbl.Props.FirstRow), BandedRows: bool(tbl.Props.BandRow),
	}
	// The editor needs every column and row to have a size; the frame is
	// what they add up to, as a row PowerPoint grew to fit its text is
	// taller than the frame says.
	out.Frame.Width, out.Frame.Height = 0, 0
	for c, col := range tbl.Grid {
		out.Columns[c] = math.Max(round(float64(col.W)*t.sx/s.scale), 1)
		out.Frame.Width += out.Columns[c]
	}
	for r, row := range tbl.Rows {
		out.Rows[r] = math.Max(round(float64(row.H)*t.sy/s.scale), 1)
		out.Frame.Height += out.Rows[r]
		out.Cells[r] = make([]outCell, cols)
		for c := range min(len(row.Cells), cols) {
			out.Cells[r][c] = s.tableCell(row.Cells[c])
		}
	}
	out.Frame.Width, out.Frame.Height = round(out.Frame.Width), round(out.Frame.Height)
	return []outElement{out}, nil
}

// tableCell converts one cell. A cell a merge covers keeps its text but no
// span; the editor finds it covered by its anchor's.
func (s *slideReader) tableCell(tc xTableCell) outCell {
	var cell outCell
	if !tc.HMerge && !tc.VMerge {
		if tc.GridSpan > 1 {
			cell.ColSpan = int(min(tc.GridSpan, maxTableColumns))
		}
		if tc.RowSpan > 1 {
			cell.RowSpan = int(min(tc.RowSpan, maxTableRows))
		}
	}
	if tc.Text != nil {
		lists := []*xListStyle{tc.Text.ListStyle, s.defaultText}
		for _, p := range tc.Text.Paragraphs {
			cell.Paragraphs = append(cell.Paragraphs, s.paragraphs(p, lists, "")...)
		}
		// One empty line is a blank cell, which the editor writes as none.
		if len(cell.Paragraphs) == 1 && len(cell.Paragraphs[0].Runs) == 0 {
			cell.Paragraphs = nil
		}
	}
	if props := tc.Props; props != nil {
		cell.Anchor = map[string]string{"ctr": "middle", "b": "bottom"}[props.Anchor]
		cell.Fill = s.fill(props.xFill, nil)
		borders := outBorders{
			Top:    s.stroke(props.Top, nil),
			Right:  s.stroke(props.Right, nil),
			Bottom: s.stroke(props.Bottom, nil),
			Left:   s.stroke(props.Left, nil),
		}
		if borders != (outBorders{}) {
			cell.Borders = &borders
		}
	}
	return cell
}
