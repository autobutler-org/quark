import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/table_sample.dart';

SlideTableCell text(String s, {int rowSpan = 1, int colSpan = 1}) =>
    SlideTableCell(
      paragraphs: [TextParagraph.plain(s)],
      rowSpan: rowSpan,
      colSpan: colSpan,
    );

void main() {
  group('geometry', () {
    final table = sampleTable();

    test('columns and rows start where the ones before end', () {
      expect(table.rowCount, 3);
      expect(table.columnCount, 3);
      expect(table.columnStart(0), 0);
      expect(table.columnStart(2), 220);
      expect(table.columnStart(3), 300);
      expect(table.rowStart(3), 120);
    });

    test('a merged area has one anchor and covers the rest', () {
      expect(table.anchorOf(2, 1), (row: 2, column: 0));
      expect(table.isCovered(2, 1), isTrue);
      expect(table.isCovered(2, 0), isFalse);
      expect(table.areaOf(2, 1),
          const CellRange(top: 2, left: 0, bottom: 2, right: 1));
      expect(
          table.cellBox(2, 1), (x: 0.0, y: 80.0, width: 220.0, height: 40.0));
    });

    test('cellAt finds the anchor under a table-local point', () {
      expect(table.cellAt(50, 10), (row: 0, column: 0));
      expect(table.cellAt(150, 50), (row: 1, column: 1));
      expect(table.cellAt(150, 100), (row: 2, column: 0));
      expect(table.cellAt(299, 119), (row: 2, column: 2));
      expect(table.cellAt(301, 10), isNull);
      expect(table.cellAt(-1, 10), isNull);
    });

    test('expandToMerges grows a range until it cuts through no merge', () {
      expect(
        table.expandToMerges(const CellRange.single(2, 1)),
        const CellRange(top: 2, left: 0, bottom: 2, right: 1),
      );
      expect(
        table.expandToMerges(
            const CellRange(top: 1, left: 1, bottom: 2, right: 1)),
        const CellRange(top: 1, left: 0, bottom: 2, right: 1),
      );
    });

    test('a cell text box sits inside the padding with the table id', () {
      final box = table.cellTextBox(0, 1);
      expect(box.id, 'tbl');
      expect(box.frame.x, 100 + TableElement.cellPaddingX);
      expect(box.frame.y, TableElement.cellPaddingY);
      expect(box.frame.width, 120 - 2 * TableElement.cellPaddingX);
      expect(box.plainText, 'Q3');
      expect(box.autoFit, TextAutoFit.fixed);
      expect(table.cellTextBox(0, 2).anchor, TextAnchor.middle);
    });

    test('plainText reads row by row, skipping covered cells', () {
      expect(table.plainText, 'Region\tQ3\tQ4\nNorth\t12\t\nTotal\t30');
    });
  });

  group('fills', () {
    test('the header takes the accent, every other body row the band', () {
      final table = sampleTable();
      expect(table.fillAt(0, 0), const SlideColor(0xFF224488));
      expect(table.fillAt(1, 0), isNull);
      expect(table.fillAt(1, 1), const SlideColor.theme(ThemeColor.accent2));
      expect(table.fillAt(2, 2), TableElement.bandColor);
      // A covered cell shows its anchor's fill.
      expect(table.fillAt(2, 1), table.fillAt(2, 0));
    });

    test('without a header the first row is the first body row', () {
      final table = sampleTable().copyWith(headerRow: false);
      expect(table.fillAt(0, 0), isNull);
      expect(table.fillAt(1, 0), TableElement.bandColor);
      expect(sampleTable().copyWith(bandedRows: false).fillAt(2, 2), isNull);
    });
  });

  group('edges', () {
    test('the cell above or to the left wins where it has a line', () {
      final table = sampleTable();
      expect(table.edgeAbove(1, 1), thin());
      expect(table.edgeAbove(2, 1)!.dash, StrokeDash.dash);
      expect(table.edgeBefore(1, 2)!.width, 3);
      expect(table.edgeAbove(0, 0), isNull);
    });

    test('no line is drawn inside a merged area', () {
      final table = sampleTable().copyWith(
        cells: [
          ...sampleTable().cells.take(2),
          [
            SlideTableCell(colSpan: 2, borders: CellBorders.all(thin())),
            SlideTableCell(borders: CellBorders.all(thin())),
            const SlideTableCell(),
          ],
        ],
      );
      expect(table.edgeBefore(2, 1), isNull);
      expect(table.edgeBefore(2, 2), thin());
    });
  });

  group('withFrame', () {
    test('scales every column and row in proportion', () {
      final table = sampleTable();
      final resized =
          table.withFrame(table.frame.copyWith(width: 600, height: 60));
      expect(resized.columnWidths, [200, 240, 160]);
      expect(resized.rowHeights, [20, 20, 20]);
    });

    test('a move keeps the sizes as they are', () {
      final table = sampleTable();
      final moved = table.withFrame(table.frame.translate(10, 10));
      expect(moved.columnWidths, table.columnWidths);
      expect(moved.rowHeights, table.rowHeights);
    });
  });

  group('normalizedSpans', () {
    test('clips a merge to the grid', () {
      final cells = TableElement.normalizedSpans([
        [text('a', rowSpan: 5, colSpan: 5), const SlideTableCell()],
        [const SlideTableCell(), const SlideTableCell()],
      ]);
      expect(cells[0][0].rowSpan, 2);
      expect(cells[0][0].colSpan, 2);
    });

    test('undoes a merge that would overlap an earlier one', () {
      final cells = TableElement.normalizedSpans([
        [text('a', colSpan: 2), const SlideTableCell()],
        [const SlideTableCell(), text('b', rowSpan: 1)],
      ]);
      expect(cells[0][0].colSpan, 2);
      final overlapping = TableElement.normalizedSpans([
        [text('a', rowSpan: 2), text('b', rowSpan: 2)],
        [const SlideTableCell(), const SlideTableCell()],
      ]);
      expect(overlapping[0][1].rowSpan, 2);
      final clash = TableElement.normalizedSpans([
        [text('a', colSpan: 2), text('b', rowSpan: 2)],
        [const SlideTableCell(), const SlideTableCell()],
      ]);
      expect(clash[0][0].colSpan, 2);
      expect(clash[0][1].isMerged, isFalse);
    });
  });

  test('a table equals its copy and differs by a cell', () {
    expect(sampleTable(), sampleTable());
    expect(sampleTable().hashCode, sampleTable().hashCode);
    final changed = setTableCellText(sampleTable(), 1, 2, [
      TextParagraph.plain('x'),
    ]);
    expect(changed, isNot(sampleTable()));
  });

  test('a table reads to a screen reader as its size', () {
    expect(
        defaultSlideElementLabel(sampleTable()), 'Table, 3 rows by 3 columns');
    expect(defaultSlideTableCellLabel(1, 2, 'Revenue'),
        'Row 2, column 3: Revenue');
    expect(defaultSlideTableCellLabel(0, 0, ' '), 'Row 1, column 1: empty');
  });
}
