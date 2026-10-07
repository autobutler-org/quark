package pptxutil

// cspell:ignore cNvGraphicFramePr graphicFrameLocks gridCol gridSpan hMerge lnB lnL lnR lnT marB marL marR marT tbl tblGrid tblPr tc tcPr tr vMerge xfrm

// Table limits, as quark_slides' TableElement has them: a table past them is
// not a table the editor opens.
const (
	maxTableRows    = 500
	maxTableColumns = 100
	maxTableCells   = 5_000
)

// The editor's table geometry and colors, in slide units and .qslide colors.
const (
	// cellPaddingX and cellPaddingY are the space between a cell's edges and
	// its text, TableElement.cellPaddingX and cellPaddingY.
	cellPaddingX = 14.0
	cellPaddingY = 8.0
	// defaultTableAccent fills a header row that sets no accent.
	defaultTableAccent = "theme:accent1"
	// tableBandColor fills every other body row of a banded table.
	tableBandColor = "theme:background2"
	// headerTextColor is the color of header text that sets none.
	headerTextColor = "theme:background"
	// tableURI is the graphic data a table's graphic frame holds.
	tableURI = "http://schemas.openxmlformats.org/drawingml/2006/table"
)

// tableGrid is a table's cells with its merges worked out as the editor
// works them out: clipped to the grid, and a merge that would overlap an
// earlier one undone.
type tableGrid struct {
	el         *qslideElement
	rows, cols int
	// anchor is the merge anchor of each cell, the cell itself when no merge
	// covers it.
	anchor [][][2]int
	// span is each anchor's rows and columns; 1 by 1 for any other cell.
	span [][][2]int
}

// newTableGrid reads el's grid, or reports false for a table the editor
// would refuse: no rows or columns, past the limits, or cells that do not
// fill the grid.
func newTableGrid(el *qslideElement) (*tableGrid, bool) {
	rows, cols := len(el.Rows), len(el.Columns)
	if rows == 0 || cols == 0 || rows > maxTableRows || cols > maxTableColumns ||
		rows*cols > maxTableCells || len(el.Cells) != rows {
		return nil, false
	}
	for _, row := range el.Cells {
		if len(row) != cols {
			return nil, false
		}
	}
	g := &tableGrid{el: el, rows: rows, cols: cols}
	g.anchor = make([][][2]int, rows)
	g.span = make([][][2]int, rows)
	taken := make([][]bool, rows)
	for r := range rows {
		g.anchor[r] = make([][2]int, cols)
		g.span[r] = make([][2]int, cols)
		taken[r] = make([]bool, cols)
		for c := range cols {
			g.anchor[r][c] = [2]int{r, c}
			g.span[r][c] = [2]int{1, 1}
		}
	}
	for r := range rows {
		for c := range cols {
			if taken[r][c] {
				continue
			}
			cell := el.Cells[r][c]
			rs := min(max(cell.RowSpan, 1), rows-r)
			cs := min(max(cell.ColSpan, 1), cols-c)
			for i := r; i < r+rs; i++ {
				for j := c; j < c+cs; j++ {
					if taken[i][j] {
						rs, cs = 1, 1
					}
				}
			}
			g.span[r][c] = [2]int{rs, cs}
			for i := r; i < r+rs; i++ {
				for j := c; j < c+cs; j++ {
					taken[i][j] = true
					g.anchor[i][j] = [2]int{r, c}
				}
			}
		}
	}
	return g, true
}

// edgeAbove is the line along the top of cell r, c — the table's bottom when
// r is the row count — as TableElement.edgeAbove draws it: the cell above
// wins where it has one, and inside a merged area there is none.
func (g *tableGrid) edgeAbove(r, c int) *qslideStroke {
	if r > 0 && r < g.rows && g.anchor[r-1][c] == g.anchor[r][c] {
		return nil
	}
	if r > 0 && g.el.Cells[r-1][c].Borders.Bottom != nil {
		return g.el.Cells[r-1][c].Borders.Bottom
	}
	if r < g.rows {
		return g.el.Cells[r][c].Borders.Top
	}
	return nil
}

// edgeBefore is the line along the left of cell r, c — the table's right
// when c is the column count — as TableElement.edgeBefore draws it.
func (g *tableGrid) edgeBefore(r, c int) *qslideStroke {
	if c > 0 && c < g.cols && g.anchor[r][c-1] == g.anchor[r][c] {
		return nil
	}
	if c > 0 && g.el.Cells[r][c-1].Borders.Right != nil {
		return g.el.Cells[r][c-1].Borders.Right
	}
	if c < g.cols {
		return g.el.Cells[r][c].Borders.Left
	}
	return nil
}

// fill is the .qslide color drawn under cell r, c, as TableElement.fillAt
// has it: its anchor's own, the accent in a header row, the band color on
// every other banded body row, or "" for none.
func (g *tableGrid) fill(r, c int) string {
	a := g.anchor[r][c]
	if own := g.el.Cells[a[0]][a[1]].Fill; own != "" {
		return own
	}
	if g.el.HeaderRow && a[0] == 0 {
		if g.el.Accent != "" {
			return g.el.Accent
		}
		return defaultTableAccent
	}
	body := a[0]
	if g.el.HeaderRow {
		body--
	}
	if g.el.BandedRows && body%2 == 1 {
		return tableBandColor
	}
	return ""
}

// scaled is sizes scaled to add up to total, as the editor fits a table's
// columns and rows to its frame.
func scaled(sizes []float64, total float64) []float64 {
	sum := 0.0
	for _, v := range sizes {
		sum += v
	}
	out := make([]float64, len(sizes))
	for i, v := range sizes {
		out[i] = v
		if sum > 0 {
			out[i] = v * total / sum
		}
	}
	return out
}

// writeTable writes a table as a graphic frame holding an a:tbl: its grid,
// its rows, and each cell's text, fill, edges and merge. Every edge and fill
// is written out, so the table needs no table style to look as the editor
// draws it. A table the editor would refuse is left out.
func (s *slideWriter) writeTable(el qslideElement) {
	g, ok := newTableGrid(&el)
	if !ok {
		return
	}
	columns := scaled(el.Columns, el.Frame.Width)
	rows := scaled(el.Rows, el.Frame.Height)

	s.out.put(`<p:graphicFrame><p:nvGraphicFramePr>`)
	s.nonVisual(s.id(), "Table", "")
	s.out.put(`<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>`)
	s.transform("p:xfrm", el.Frame, "", "")
	s.out.put(`<a:graphic><a:graphicData uri="` + tableURI + `"><a:tbl><a:tblPr`)
	if el.HeaderRow {
		s.out.put(` firstRow="1"`)
	}
	if el.BandedRows {
		s.out.put(` bandRow="1"`)
	}
	s.out.put(`/><a:tblGrid>`)
	for _, w := range columns {
		s.out.printf(`<a:gridCol w="%d"/>`, s.size(w))
	}
	s.out.put(`</a:tblGrid>`)

	body := roleStyle(s.theme, "body")
	header := body
	if c, ok := resolveColor(headerTextColor, s.theme); ok {
		header.color = &c
	}
	for r := range g.rows {
		s.out.printf(`<a:tr h="%d">`, s.size(rows[r]))
		style := body
		if el.HeaderRow && r == 0 {
			style = header
		}
		for c := range g.cols {
			s.writeTableCell(g, r, c, style)
		}
		s.out.put(`</a:tr>`)
	}
	s.out.put(`</a:tbl></a:graphicData></a:graphic></p:graphicFrame>`)
}

// writeTableCell writes cell r, c: an anchor with its gridSpan and rowSpan,
// or a cell a merge covers with hMerge or vMerge, as PowerPoint writes them.
func (s *slideWriter) writeTableCell(g *tableGrid, r, c int, style runStyle) {
	cell := g.el.Cells[r][c]
	a := g.anchor[r][c]
	span := g.span[a[0]][a[1]]
	s.out.put(`<a:tc`)
	switch {
	case a == [2]int{r, c}:
		if span[1] > 1 {
			s.out.printf(` gridSpan="%d"`, span[1])
		}
		if span[0] > 1 {
			s.out.printf(` rowSpan="%d"`, span[0])
		}
	case c == a[1]:
		// The first cell of a later row of a merge spans its columns too.
		if span[1] > 1 {
			s.out.printf(` gridSpan="%d"`, span[1])
		}
		s.out.put(` vMerge="1"`)
	default:
		s.out.put(` hMerge="1"`)
		if r > a[0] {
			s.out.put(` vMerge="1"`)
		}
	}
	s.out.put(`><a:txBody><a:bodyPr/><a:lstStyle/>`)
	if len(cell.Paragraphs) == 0 {
		s.out.put(`<a:p>`)
		s.writeRunProps("a:endParaRPr", qslideRun{}, style)
		s.out.put(`</a:p>`)
	}
	for _, p := range cell.Paragraphs {
		s.writeParagraph(p, style)
	}
	anchor := map[string]string{"middle": "ctr", "bottom": "b"}[g.el.Cells[a[0]][a[1]].Anchor]
	if anchor == "" {
		anchor = "t"
	}
	s.out.printf(`</a:txBody><a:tcPr marL="%d" marR="%d" marT="%d" marB="%d" anchor="%s">`,
		s.size(cellPaddingX), s.size(cellPaddingX), s.size(cellPaddingY), s.size(cellPaddingY), anchor)
	for _, edge := range []struct {
		tag    string
		stroke *qslideStroke
	}{
		{"a:lnL", g.edgeBefore(r, c)},
		{"a:lnR", g.edgeBefore(r, c+1)},
		{"a:lnT", g.edgeAbove(r, c)},
		{"a:lnB", g.edgeAbove(r+1, c)},
	} {
		if edge.stroke == nil {
			s.out.printf(`<%s w="0"><a:noFill/></%s>`, edge.tag, edge.tag)
			continue
		}
		s.writeLineProps(edge.tag, *edge.stroke, 1, "", "")
	}
	if fill, ok := resolveColor(g.fill(r, c), s.theme); ok {
		s.out.put(solidFill(fill, 1))
	} else {
		s.out.put(`<a:noFill/>`)
	}
	s.out.put(`</a:tcPr></a:tc>`)
}
