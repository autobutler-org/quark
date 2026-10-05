import 'package:quark_slides/quark_slides.dart';

/// A thin black stroke, for borders.
Stroke thin() => Stroke(width: 1);

/// A 3 × 3 table `tbl` at (100, 100), 300 × 120 units: a header row and
/// banded rows, a literal accent, rich text in the header, a cell merged
/// across two columns in the last row, a role-colored fill, a cell anchored
/// in the middle and every kind of border.
TableElement sampleTable() => TableElement(
      id: 'tbl',
      frame: ElementFrame(x: 100, y: 100, width: 300, height: 120),
      columnWidths: const [100, 120, 80],
      rowHeights: const [40, 40, 40],
      headerRow: true,
      bandedRows: true,
      accent: const SlideColor(0xFF224488),
      cells: [
        [
          const SlideTableCell(
            paragraphs: [
              TextParagraph([TextRun('Region', bold: true)]),
            ],
          ),
          SlideTableCell(
            paragraphs: const [
              TextParagraph([TextRun('Q3')])
            ],
            borders: CellBorders(bottom: thin()),
          ),
          const SlideTableCell(
            paragraphs: [
              TextParagraph([TextRun('Q4')])
            ],
            anchor: TextAnchor.middle,
          ),
        ],
        [
          const SlideTableCell(paragraphs: [
            TextParagraph([TextRun('North')])
          ]),
          SlideTableCell(
            paragraphs: const [
              TextParagraph([TextRun('12')])
            ],
            fill: const SlideColor.theme(ThemeColor.accent2),
            borders: CellBorders.all(
              Stroke(
                color: const SlideColor.theme(ThemeColor.text2),
                width: 3,
                dash: StrokeDash.dash,
              ),
            ),
          ),
          const SlideTableCell(),
        ],
        [
          const SlideTableCell(
            paragraphs: [
              TextParagraph([TextRun('Total')])
            ],
            colSpan: 2,
          ),
          const SlideTableCell(),
          const SlideTableCell(paragraphs: [
            TextParagraph([TextRun('30')])
          ]),
        ],
      ],
    );

/// A deck with [sampleTable] on slide `s1` and a smaller table `inner`
/// grouped with a shape on slide `s2`. `test/fixtures/table_sample.qslide`
/// is its golden encoding.
Presentation tableSamplePresentation() => Presentation(
      title: 'Tables',
      slides: [
        Slide(id: 's1', elements: [sampleTable()]),
        Slide(
          id: 's2',
          elements: [
            GroupElement(
              id: 'g',
              frame: ElementFrame(x: 0, y: 0, width: 200, height: 100),
              children: [
                TableElement(
                  id: 'inner',
                  frame: ElementFrame(x: 0, y: 0, width: 200, height: 50),
                  columnWidths: const [100, 100],
                  rowHeights: const [50],
                  cells: const [
                    [SlideTableCell(), SlideTableCell()],
                  ],
                ),
                ShapeElement(
                  id: 'sh',
                  frame: ElementFrame(x: 0, y: 50, width: 200, height: 50),
                ),
              ],
            ),
          ],
        ),
      ],
    );
