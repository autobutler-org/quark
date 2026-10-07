import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/table_sample.dart';

/// A 1920×1080 deck with one slide `s` holding [sampleTable] (`tbl`) and a
/// shape `box`.
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            sampleTable(),
            ShapeElement(
              id: 'box',
              frame: ElementFrame(x: 0, y: 0, width: 10, height: 10),
            ),
          ],
        ),
      ],
    );

void main() {
  late SlideDocumentController doc;
  var next = 0;
  setUp(() {
    next = 0;
    doc = SlideDocumentController(deck(), newId: () => 'n${next++}');
  });

  TableElement table([String id = 'tbl']) =>
      doc.presentation.slideById('s')!.findElement(id)! as TableElement;

  String text(int row, int column) => table().cell(row, column).plainText;

  /// Checks that [command] is one undo step that undo and redo replay.
  void oneStep(void Function() command) {
    final before = doc.presentation;
    command();
    final after = doc.presentation;
    expect(after, isNot(before));
    expect(doc.undo(), isTrue);
    expect(doc.presentation, before);
    expect(doc.canUndo, isFalse);
    expect(doc.redo(), isTrue);
    expect(doc.presentation, after);
  }

  group('insertTable', () {
    test('centers a header-and-banded table on the slide, in front', () {
      late String id;
      oneStep(() => id = doc.insertTable('s', 3, 4));
      final t = table(id);
      expect(t.rowCount, 3);
      expect(t.columnCount, 4);
      expect(t.headerRow, isTrue);
      expect(t.bandedRows, isTrue);
      expect(
          t.frame.width, 4 * SlideDocumentController.defaultTableColumnWidth);
      expect(t.frame.height, 3 * SlideDocumentController.defaultTableRowHeight);
      expect(t.frame.x, (1920 - t.frame.width) / 2);
      expect(t.cell(1, 1).borders, CellBorders.all(TableElement.defaultBorder));
      expect(doc.presentation.slides.single.elements.last.id, id);
    });

    test('narrows a wide table to fit the slide', () {
      final t = table(doc.insertTable('s', 1, 20));
      expect(t.frame.width, 1920 * 0.8);
      expect(t.columnWidths.first, closeTo(1920 * 0.8 / 20, 1e-9));
    });

    test('fills a frame it is given', () {
      final id = doc.insertTable(
        's',
        2,
        2,
        frame: ElementFrame(x: 10, y: 20, width: 400, height: 100),
      );
      expect(table(id).columnWidths, [200, 200]);
      expect(table(id).rowHeights, [50, 50]);
    });

    test('refuses a size past the caps', () {
      expect(() => doc.insertTable('s', 0, 3), throwsArgumentError);
      expect(
        () => doc.insertTable('s', TableElement.maxRows + 1, 1),
        throwsArgumentError,
      );
      expect(doc.canUndo, isFalse);
    });
  });

  group('rows and columns', () {
    test('insertTableRow above and below, growing the table', () {
      oneStep(() => doc.insertTableRow('s', 'tbl', 1));
      expect(table().rowCount, 4);
      expect(text(1, 0), '');
      expect(text(2, 0), 'North');
      expect(table().frame.height, 160);
      doc.insertTableRow('s', 'tbl', 3, after: true);
      expect(table().rowCount, 5);
      expect(text(3, 0), 'Total');
      expect(text(4, 2), '');
    });

    test('a row inserted inside a merge widens the merge', () {
      doc.mergeCells(
          's', 'tbl', const CellRange(top: 0, left: 2, bottom: 1, right: 2));
      doc.insertTableRow('s', 'tbl', 0, after: true);
      expect(table().cell(0, 2).rowSpan, 3);
      expect(table().isCovered(1, 2), isTrue);
    });

    test('insertTableColumn left and right, growing the table', () {
      oneStep(() => doc.insertTableColumn('s', 'tbl', 0));
      expect(table().columnCount, 4);
      expect(text(0, 1), 'Region');
      expect(table().frame.width, 400);
      expect(table().columnWidths, [100, 100, 120, 80]);
      // The merge on the last row now starts one column further.
      expect(table().cell(2, 1).colSpan, 2);
      doc.insertTableColumn('s', 'tbl', 1, after: true);
      // Inserted inside the merge: it widens.
      expect(table().cell(2, 1).colSpan, 3);
    });

    test('deleteTableRow shrinks the table and keeps a merge anchored', () {
      oneStep(() => doc.deleteTableRow('s', 'tbl', 0));
      expect(table().rowCount, 2);
      expect(text(0, 0), 'North');
      expect(table().frame.height, 80);
    });

    test('deleting the first row of a merge moves its text down', () {
      doc.mergeCells(
          's', 'tbl', const CellRange(top: 0, left: 2, bottom: 2, right: 2));
      expect(text(0, 2), 'Q4\n30');
      doc.deleteTableRow('s', 'tbl', 0);
      expect(table().cell(0, 2).rowSpan, 2);
      expect(text(0, 2), 'Q4\n30');
    });

    test('deleteTableColumn through a merge narrows it', () {
      oneStep(() => doc.deleteTableColumn('s', 'tbl', 1));
      expect(table().columnCount, 2);
      expect(table().columnWidths, [100, 80]);
      expect(table().cell(2, 0).isMerged, isFalse);
      expect(text(2, 0), 'Total');
      expect(table().frame.width, 180);
    });

    test('deleting the anchor column of a merge keeps its text', () {
      doc.deleteTableColumn('s', 'tbl', 0);
      expect(text(2, 0), 'Total');
      expect(text(0, 0), 'Q3');
    });

    test('deleting every row or column deletes the table', () {
      oneStep(() => doc.deleteTableRow('s', 'tbl', 0, count: 3));
      expect(doc.presentation.slides.single.findElement('tbl'), isNull);
      doc.undo();
      doc.deleteTableColumn('s', 'tbl', 0, count: 3);
      expect(doc.presentation.slides.single.findElement('tbl'), isNull);
    });
  });

  group('sizes', () {
    test('a column takes its width from its right-hand neighbor', () {
      oneStep(() => doc.setTableColumnWidth('s', 'tbl', 0, 150));
      expect(table().columnWidths, [150, 70, 80]);
      expect(table().frame.width, 300);
    });

    test('a neighbor never goes under the minimum', () {
      doc.setTableColumnWidth('s', 'tbl', 0, 1000);
      expect(
          table().columnWidths, [220 - minTableCellSize, minTableCellSize, 80]);
      doc.setTableColumnWidth('s', 'tbl', 0, 0);
      expect(table().columnWidths.first, minTableCellSize);
    });

    test('the last column changes the table width', () {
      doc.setTableColumnWidth('s', 'tbl', 2, 200);
      expect(table().columnWidths, [100, 120, 200]);
      expect(table().frame.width, 420);
    });

    test('a row changes the table height', () {
      oneStep(() => doc.setTableRowHeight('s', 'tbl', 1, 90));
      expect(table().rowHeights, [40, 90, 40]);
      expect(table().frame.height, 170);
      doc.setTableRowHeight('s', 'tbl', 1, 1);
      expect(table().rowHeights[1], minTableCellSize);
    });

    test('resizing the table scales its columns and rows', () {
      doc.resizeElement('s', 'tbl', width: 600, height: 240);
      expect(table().columnWidths, [200, 240, 160]);
      expect(table().rowHeights, [80, 80, 80]);
    });
  });

  group('text', () {
    test('setCellText replaces a cell as one step', () {
      oneStep(() => doc.setCellText(
            's',
            'tbl',
            1,
            2,
            const [
              TextParagraph([TextRun('7', italic: true)]),
            ],
          ));
      expect(text(1, 2), '7');
    });

    test('a covered cell writes to its merge anchor', () {
      doc.setCellText('s', 'tbl', 2, 1, [TextParagraph.plain('Sum')]);
      expect(text(2, 0), 'Sum');
      expect(text(2, 1), '');
    });

    test('a row grows to fit its text when the controller can measure', () {
      final measured = SlideDocumentController(
        deck(),
        measureText: (box, theme) => box.paragraphs.length * 30.0,
      );
      measured.setCellText('s', 'tbl', 1, 0, [
        for (var i = 0; i < 4; i++) TextParagraph.plain('line $i'),
      ]);
      final t = measured.presentation.slides.single.findElement('tbl')!
          as TableElement;
      expect(t.rowHeights[1], 4 * 30 + 2 * TableElement.cellPaddingY);
      expect(t.frame.height, t.rowHeights.fold(0.0, (a, b) => a + b));
      // It does not shrink back on its own.
      measured.setCellText('s', 'tbl', 1, 0, [TextParagraph.plain('x')]);
      expect(
        (measured.presentation.slides.single.findElement('tbl')!
                as TableElement)
            .rowHeights[1],
        t.rowHeights[1],
      );
    });

    test('a cell is not a text box to editText', () {
      expect(
        () => doc.editText('s', 'tbl', const []),
        throwsArgumentError,
      );
      expect(
        () => doc.setCellText('s', 'box', 0, 0, const []),
        throwsArgumentError,
      );
      expect(
          () => doc.setCellText('s', 'tbl', 9, 0, const []), throwsRangeError);
    });
  });

  group('formatCells', () {
    const all = CellRange(top: 0, left: 0, bottom: 2, right: 2);

    test('bolds, colors and aligns every cell of a range as one step', () {
      oneStep(() => doc.formatCells(
            's',
            'tbl',
            const CellRange(top: 1, left: 0, bottom: 1, right: 1),
            const CellFormat(
              text: TextFormat(
                bold: true,
                italic: true,
                color: SlideColor.theme(ThemeColor.accent3),
                alignment: TextAlignment.center,
                anchor: TextAnchor.bottom,
              ),
            ),
          ));
      final cell = table().cell(1, 1);
      final run = cell.paragraphs.single.runs.single;
      expect(run.bold, isTrue);
      expect(run.italic, isTrue);
      expect(run.color, const SlideColor.theme(ThemeColor.accent3));
      expect(cell.paragraphs.single.alignment, TextAlignment.center);
      expect(cell.anchor, TextAnchor.bottom);
      expect(table().cell(1, 2).anchor, TextAnchor.top);
    });

    test('fills and clears a fill', () {
      doc.formatCells('s', 'tbl', const CellRange.single(0, 0),
          const CellFormat(fill: SlideColor(0xFFFF0000)));
      expect(table().fillAt(0, 0), const SlideColor(0xFFFF0000));
      doc.formatCells('s', 'tbl', const CellRange.single(0, 0),
          const CellFormat(fill: null));
      expect(table().fillAt(0, 0), table().accent);
    });

    test('a range cutting through a merge formats the whole merge', () {
      doc.formatCells('s', 'tbl', const CellRange.single(2, 1),
          const CellFormat(fill: SlideColor.white));
      expect(table().cell(2, 0).fill, SlideColor.white);
    });

    test('the border presets set both sides of each edge', () {
      final line = Stroke(width: 5);
      doc.formatCells(
          's', 'tbl', all, const CellFormat(borders: CellBorderPreset.none));
      for (var r = 0; r <= 3; r++) {
        for (var c = 0; c < 3; c++) {
          expect(table().edgeAbove(r, c), isNull, reason: 'above $r, $c');
        }
      }
      doc.formatCells(
        's',
        'tbl',
        const CellRange(top: 0, left: 0, bottom: 1, right: 1),
        CellFormat(borders: CellBorderPreset.outside, borderStroke: line),
      );
      expect(table().edgeAbove(0, 0), line);
      expect(table().edgeAbove(2, 1), line);
      expect(table().cell(2, 1).borders.top, line);
      expect(table().edgeBefore(0, 2), line);
      expect(table().cell(0, 2).borders.left, line);
      expect(table().edgeAbove(1, 0), isNull);
      expect(table().edgeBefore(0, 1), isNull);

      doc.formatCells(
        's',
        'tbl',
        const CellRange(top: 0, left: 0, bottom: 1, right: 1),
        const CellFormat(borders: CellBorderPreset.inside),
      );
      expect(table().edgeAbove(1, 0), TableElement.defaultBorder);
      expect(table().edgeBefore(0, 1), TableElement.defaultBorder);
    });

    test('each single-edge preset draws only its edge', () {
      const range = CellRange(top: 0, left: 0, bottom: 1, right: 1);
      final expected = {
        CellBorderPreset.top: (0, 0, true),
        CellBorderPreset.bottom: (2, 0, true),
        CellBorderPreset.left: (0, 0, false),
        CellBorderPreset.right: (0, 2, false),
        CellBorderPreset.insideHorizontal: (1, 0, true),
        CellBorderPreset.insideVertical: (0, 1, false),
      };
      for (final MapEntry(key: preset, value: (r, c, above))
          in expected.entries) {
        doc.formatCells(
            's', 'tbl', all, const CellFormat(borders: CellBorderPreset.none));
        doc.formatCells('s', 'tbl', range, CellFormat(borders: preset));
        final t = table();
        final drawn = [
          for (var r = 0; r <= 3; r++)
            for (var c = 0; c < 3; c++)
              if (t.edgeAbove(r, c) != null) ('above', r, c),
          for (var r = 0; r < 3; r++)
            for (var c = 0; c <= 3; c++)
              if (t.edgeBefore(r, c) != null) ('before', r, c),
        ];
        final want = above
            ? [('above', r, c), ('above', r, c + 1)]
            : [('before', r, c), ('before', r + 1, c)];
        expect(drawn, want, reason: preset.name);
      }
    });
  });

  group('merging', () {
    test('mergeCells joins the text into the anchor as one step', () {
      const range = CellRange(top: 0, left: 1, bottom: 1, right: 2);
      oneStep(() => doc.mergeCells('s', 'tbl', range));
      final t = table();
      expect(t.cell(0, 1).rowSpan, 2);
      expect(t.cell(0, 1).colSpan, 2);
      expect(t.cell(0, 1).plainText, 'Q3\nQ4\n12');
      expect(t.isCovered(1, 2), isTrue);
      expect(t.cell(1, 1).plainText, '');
      expect(t.cellBox(1, 2), (x: 100.0, y: 0.0, width: 200.0, height: 80.0));
    });

    test('merging a range that cuts a merge takes the merge in', () {
      doc.mergeCells(
          's', 'tbl', const CellRange(top: 1, left: 1, bottom: 2, right: 1));
      final t = table();
      expect(t.cell(1, 0).rowSpan, 2);
      expect(t.cell(1, 0).colSpan, 2);
      expect(t.cell(1, 0).plainText, 'North\n12\nTotal');
      expect(t.cell(2, 0).isMerged, isFalse);
    });

    test('merging one cell changes nothing and records nothing', () {
      doc.mergeCells('s', 'tbl', const CellRange.single(0, 0));
      expect(doc.canUndo, isFalse);
    });

    test('unmergeCells splits every merge it touches as one step', () {
      oneStep(() => doc.unmergeCells('s', 'tbl', const CellRange.single(2, 1)));
      expect(table().cell(2, 0).isMerged, isFalse);
      expect(text(2, 0), 'Total');
      expect(text(2, 1), '');
      expect(table().isCovered(2, 1), isFalse);
    });

    test('merge, then unmerge, then undo both', () {
      final before = doc.presentation;
      doc.mergeCells(
          's', 'tbl', const CellRange(top: 0, left: 0, bottom: 1, right: 1));
      doc.unmergeCells('s', 'tbl', const CellRange.single(0, 0));
      expect(table().cell(0, 0).plainText, 'Region\nQ3\nNorth\n12');
      expect(doc.undo(), isTrue);
      expect(doc.undo(), isTrue);
      expect(doc.presentation, before);
    });
  });

  group('setTableStyle', () {
    test('turns the header and bands off and changes the accent', () {
      oneStep(() => doc.setTableStyle('s', 'tbl',
          headerRow: false,
          bandedRows: false,
          accent: const SlideColor.theme(ThemeColor.accent4)));
      expect(table().headerRow, isFalse);
      expect(table().bandedRows, isFalse);
      expect(table().accent, const SlideColor.theme(ThemeColor.accent4));
    });

    test('setting the style it has records nothing', () {
      doc.setTableStyle('s', 'tbl', headerRow: true);
      expect(doc.canUndo, isFalse);
    });
  });

  test('table commands reach a table inside a group', () {
    final grouped = SlideDocumentController(tableSamplePresentation());
    grouped.insertTableColumn('s2', 'inner', 1, after: true);
    final group =
        grouped.presentation.slideById('s2')!.findElement('g')! as GroupElement;
    final inner = group.children.first as TableElement;
    expect(inner.columnCount, 3);
    // The group refits around the wider table.
    expect(group.frame.width, 300);
  });

  test('table commands on another element throw', () {
    expect(() => doc.insertTableRow('s', 'box', 0), throwsArgumentError);
    expect(() => doc.mergeCells('s', 'nope', const CellRange.single(0, 0)),
        throwsArgumentError);
  });

  test('copying and pasting a table keeps its cells', () {
    final ids = doc.duplicateElements('s', ['tbl']);
    final copy = table(ids.single);
    expect(copy.cells, table().cells);
    expect(copy.frame.x, table().frame.x + SlideDocumentController.pasteOffset);
  });
}
