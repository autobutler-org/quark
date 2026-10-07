import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/canvas_harness.dart';

/// A deck whose slide `s` holds a 3 × 3 table `tbl` at (360, 300), 1200 ×
/// 450 — 400 × 150 cells — with text in its first row and middle cell.
Presentation tableDeck() {
  var table = newTable(
    id: 'tbl',
    frame: ElementFrame(x: 360, y: 300, width: 1200, height: 450),
    rows: 3,
    columns: 3,
  );
  for (final (r, c, text) in [
    (0, 0, 'Region'),
    (0, 1, 'Q3'),
    (0, 2, 'Q4'),
    (1, 1, 'North'),
  ]) {
    table = setTableCellText(table, r, c, [TextParagraph.plain(text)]);
  }
  return Presentation(
    slides: [
      Slide(id: 's', elements: [table]),
    ],
  );
}

/// The screen point at the center of cell [row], [column] of `tbl`.
Offset cellCenter(WidgetTester tester, int row, int column) => slideToGlobal(
    tester, Offset(360 + 400 * column + 200.0, 300 + 150 * row + 75.0));

Finder cellKey(int row, int column) =>
    find.byKey(ValueKey(SlideTableView.cellKeyName('tbl', row, column)));

/// The editor's paragraph field that has focus.
EditableText focusedField(WidgetTester tester) => tester.widget<EditableText>(
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
    );

Future<void> typeText(WidgetTester tester, String text) async {
  final value = focusedField(tester).controller.value;
  final selection = value.selection;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(selection.start, selection.end, text),
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// When the next [tap] goes down: a second apart, so no two taps read as
/// a double tap.
var _clock = Duration.zero;

/// Taps [global] once, a second after the last tap.
Future<void> tap(WidgetTester tester, Offset global) async {
  _clock += const Duration(seconds: 1);
  final gesture = await tester.createGesture();
  await gesture.down(global, timeStamp: _clock);
  await gesture.up(timeStamp: _clock + const Duration(milliseconds: 20));
  await tester.pump();
}

void main() {
  late SlideDocumentNotifier doc;
  late SlideTableEditingController cells;
  late SlideTextEditingController editing;
  setUp(() {
    var n = 0;
    doc = SlideDocumentNotifier(tableDeck(), newId: () => 'new${n++}');
    cells = SlideTableEditingController();
    editing = SlideTextEditingController();
  });
  tearDown(() {
    cells.dispose();
    editing.dispose();
    doc.dispose();
  });

  TableElement table([String id = 'tbl']) =>
      doc.presentation.slideById('s')!.findElement(id)! as TableElement;

  Future<void> pump(WidgetTester tester, Size size, {double textScale = 1}) =>
      pumpCanvas(
        tester,
        doc,
        size: size,
        tableEditing: cells,
        textEditing: editing,
        textScale: textScale,
      );

  /// Taps the table once to select it.
  Future<void> selectTable(WidgetTester tester) async {
    await tap(tester, cellCenter(tester, 1, 1));
    expect(harness(tester).selection, {'tbl'});
  }

  group('drawing', () {
    testBothViewports('each cell is drawn and keyed, merges once',
        (tester, size) async {
      doc.controller.mergeCells(
          's', 'tbl', const CellRange(top: 2, left: 0, bottom: 2, right: 1));
      await pump(tester, size);
      expect(cellKey(0, 0), findsOne);
      expect(cellKey(2, 0), findsOne);
      expect(cellKey(2, 1), findsNothing);
      expect(find.text('North', findRichText: true), findsOne);
      final merged = tester.getSize(cellKey(2, 0));
      final single = tester.getSize(cellKey(2, 2));
      expect(merged.width, closeTo(single.width * 2, 0.5));
      expect(tester.takeException(), isNull);
    });

    testBothViewports('text keeps its slide size at a 2.0 text scale',
        (tester, size) async {
      await pump(tester, size);
      final before = tester.getSize(find.text('North', findRichText: true));
      await pump(tester, size, textScale: 2);
      expect(tester.getSize(find.text('North', findRichText: true)), before);
      expect(tester.takeException(), isNull);
    });
  });

  group('semantics', () {
    testWidgets('each cell reads its row, column and text', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, wideViewport);
      expect(find.bySemanticsLabel('Table, 3 rows by 3 columns'), findsOne);
      expect(find.bySemanticsLabel('Row 2, column 2: North'), findsOne);
      expect(find.bySemanticsLabel('Row 3, column 1: empty'), findsOne);
      handle.dispose();
    });

    testWidgets('a selected cell reads as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, wideViewport);
      await selectTable(tester);
      await tap(tester, cellCenter(tester, 1, 1));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Row 2, column 2: North')),
        isSemantics(isSelected: true, hasSelectedState: true),
      );
      handle.dispose();
    });
  });

  group('selecting cells', () {
    testBothViewports('the first tap selects the table, the next a cell',
        (tester, size) async {
      await pump(tester, size);
      await selectTable(tester);
      expect(cells.hasSelection, isFalse);
      await tap(tester, cellCenter(tester, 0, 2));
      expect(cells.tableId, 'tbl');
      expect(cells.range, const CellRange.single(0, 2));
      expect(harness(tester).selection, {'tbl'});
    });

    testBothViewports('a drag across cells selects the cells between',
        (tester, size) async {
      await pump(tester, size);
      await selectTable(tester);
      final gesture = await tester.startGesture(cellCenter(tester, 0, 0));
      await gesture.moveTo(cellCenter(tester, 1, 1));
      await gesture.moveTo(cellCenter(tester, 2, 1));
      await gesture.up();
      await tester.pump();
      expect(
          cells.range, const CellRange(top: 0, left: 0, bottom: 2, right: 1));
      expect(cells.active, (row: 0, column: 0));
      // Selecting cells moved nothing.
      expect(doc.controller.canUndo, isFalse);
      expect(table().frame.x, 360);
    });

    testBothViewports('a drag on a table not yet selected moves it',
        (tester, size) async {
      await pump(tester, size);
      final gesture = await tester.startGesture(cellCenter(tester, 1, 1));
      await gesture.moveBy(const Offset(0, 40));
      await gesture.moveBy(const Offset(0, 40));
      await gesture.up();
      await tester.pump();
      expect(table().frame.y, greaterThan(300));
      expect(harness(tester).selection, {'tbl'});
      expect(cells.hasSelection, isFalse);
    });

    testWidgets('a drag from the edge of a selected table moves it',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      // Clear of the handles: between the left edge's corner and middle.
      final edge = slideToGlobal(tester, const Offset(362, 412));
      final gesture = await tester.startGesture(edge);
      await gesture.moveBy(const Offset(0, 40));
      await gesture.moveBy(const Offset(0, 40));
      await gesture.up();
      await tester.pump();
      expect(table().frame.y, greaterThan(300));
      expect(cells.hasSelection, isFalse);
    });

    testWidgets('arrows move, Shift+arrows grow and shrink, Escape lets go',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      await tap(tester, cellCenter(tester, 1, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(cells.range, const CellRange.single(1, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(cells.range, const CellRange.single(1, 2), reason: 'stays in');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(
          cells.range, const CellRange(top: 0, left: 1, bottom: 1, right: 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(
          cells.range, const CellRange(top: 0, left: 2, bottom: 1, right: 2));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(cells.active, (row: 1, column: 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cells.hasSelection, isFalse);
      expect(harness(tester).selection, {'tbl'});
      // With no cells, the arrows nudge the table again.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(table().frame.x, 361);
    });

    testWidgets('Tab and Shift+Tab step through the cells, past merges',
        (tester) async {
      doc.controller.mergeCells(
          's', 'tbl', const CellRange(top: 1, left: 0, bottom: 1, right: 1));
      await pump(tester, wideViewport);
      await selectTable(tester);
      await tap(tester, cellCenter(tester, 0, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
          cells.range, const CellRange(top: 1, left: 0, bottom: 1, right: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(cells.range, const CellRange.single(1, 2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(cells.active, (row: 1, column: 0));
    });

    testWidgets('Delete empties the selected cells as one step',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      final gesture = await tester.startGesture(cellCenter(tester, 0, 0));
      await gesture.moveTo(cellCenter(tester, 0, 2));
      await gesture.up();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(table().plainText.split('\n').first, '\t\t');
      expect(doc.presentation.slides.single.elements, hasLength(1));
      expect(undoAll(doc), 1);
    });

    testWidgets('selecting something else lets go of the cells',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      await tap(tester, cellCenter(tester, 1, 1));
      await tap(tester, slideToGlobal(tester, const Offset(100, 100)));
      expect(cells.hasSelection, isFalse);
    });
  });

  group('editing a cell', () {
    testBothViewports('a double tap opens the cell; Escape writes it',
        (tester, size) async {
      await pump(tester, size);
      await doubleTap(tester, cellCenter(tester, 1, 1));
      expect(editing.isEditing, isTrue);
      expect(editing.elementId, 'tbl');
      expect(editing.cell, (row: 1, column: 1));
      expect(focusedField(tester).controller.text, 'North');
      await typeText(tester, ' east');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editing.isEditing, isFalse);
      expect(table().cell(1, 1).plainText, 'North east');
      expect(cells.range, const CellRange.single(1, 1));
      expect(undoAll(doc), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Enter edits the keyboard cell; Tab moves on, one step each',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(editing.cell, (row: 0, column: 0));
      await typeText(tester, '!');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(editing.cell, (row: 0, column: 1));
      expect(table().cell(0, 0).plainText, 'Region!');
      await typeText(tester, '?');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(editing.cell, (row: 0, column: 0));
      expect(table().cell(0, 1).plainText, 'Q3?');
      editing.commit();
      expect(undoAll(doc), 2);
    });

    testWidgets('formatting while editing a cell writes its runs',
        (tester) async {
      await pump(tester, wideViewport);
      await doubleTap(tester, cellCenter(tester, 1, 1));
      editing.selectAll();
      editing.toggle(TextToggle.bold);
      editing.commit();
      await tester.pump();
      expect(table().cell(1, 1).paragraphs.single.runs.single.bold, isTrue);
    });

    testWidgets('a cell that grows with its text grows its row',
        (tester) async {
      await pump(tester, wideViewport);
      await doubleTap(tester, cellCenter(tester, 2, 2));
      for (var i = 0; i < 6; i++) {
        await typeText(tester, 'word word word word word word ');
      }
      editing.commit();
      await tester.pump();
      expect(table().rowHeights[2], greaterThan(150));
      expect(
          table().frame.height, table().rowHeights.fold(0.0, (a, b) => a + b));
    });
  });

  group('grips', () {
    testBothViewports('a selected table shows a grip per inner line',
        (tester, size) async {
      await pump(tester, size);
      await selectTable(tester);
      for (final key in [
        'slide_table_column_0',
        'slide_table_column_1',
        'slide_table_row_0',
        'slide_table_row_1',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOne, reason: key);
        final box = tester.getSize(find.byKey(ValueKey(key)));
        expect(box.width, closeTo(48, 1e-6));
        expect(box.height, closeTo(48, 1e-6));
      }
    });

    testWidgets('dragging a column grip moves the line, as one step',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      final grip = tester.getCenter(
        find.byKey(const ValueKey('slide_table_column_0')),
      );
      final scale = canvasViewport(tester).scale;
      final gesture = await tester.startGesture(grip);
      await gesture.moveBy(Offset(50 * scale, 0));
      await gesture.moveBy(Offset(50 * scale, 0));
      await gesture.up();
      await tester.pump();
      expect(table().columnWidths[0], closeTo(500, 1));
      expect(table().columnWidths[1], closeTo(300, 1));
      expect(table().frame.width, closeTo(1200, 1e-6));
      expect(undoAll(doc), 1);
    });

    testWidgets('dragging a row grip makes the row and table taller',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      final grip =
          tester.getCenter(find.byKey(const ValueKey('slide_table_row_1')));
      final scale = canvasViewport(tester).scale;
      final gesture = await tester.startGesture(grip);
      await gesture.moveBy(Offset(0, 30 * scale));
      await gesture.moveBy(Offset(0, 30 * scale));
      await gesture.up();
      await tester.pump();
      expect(table().rowHeights[1], closeTo(210, 1));
      expect(table().frame.height, closeTo(510, 1));
    });

    testWidgets('the corner handle scales every column and row',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      final corner = tester.getCenter(handleKey(SlideHandle.bottomRight));
      final scale = canvasViewport(tester).scale;
      final gesture = await tester.startGesture(corner);
      await gesture.moveBy(Offset(-300 * scale, 0));
      await gesture.moveBy(Offset(-300 * scale, 0));
      await gesture.up();
      await tester.pump();
      expect(table().frame.width, closeTo(600, 1));
      for (final w in table().columnWidths) {
        expect(w, closeTo(200, 1));
      }
    });
  });

  group('the table tool', () {
    testBothViewports('a drag draws a table of the tool size, selected',
        (tester, size) async {
      await pump(tester, size);
      harness(tester).useTool(const SlideCanvasTool.table(2, 4));
      await tester.pump();
      final gesture = await tester
          .startGesture(slideToGlobal(tester, const Offset(100, 100)));
      await gesture.moveTo(slideToGlobal(tester, const Offset(500, 200)));
      await gesture.moveTo(slideToGlobal(tester, const Offset(900, 300)));
      await gesture.up();
      await tester.pump();
      final id = harness(tester).selection.single;
      final drawn = table(id);
      expect(drawn.rowCount, 2);
      expect(drawn.columnCount, 4);
      expect(drawn.frame.x, closeTo(100, 4));
      expect(drawn.frame.width, closeTo(800, 8));
      expect(harness(tester).tool, SlideCanvasTool.select);
      expect(undoAll(doc), 1);
    });

    testWidgets('a click places a default-size table', (tester) async {
      await pump(tester, wideViewport);
      harness(tester).useTool(const SlideCanvasTool.table(3, 2));
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(100, 100)));
      await tester.pump();
      final drawn = table(harness(tester).selection.single);
      expect(drawn.frame.width,
          2 * SlideDocumentController.defaultTableColumnWidth);
      expect(drawn.frame.height,
          3 * SlideDocumentController.defaultTableRowHeight);
    });

    testWidgets('the tool reads as an insert action', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, wideViewport);
      harness(tester).useTool(const SlideCanvasTool.table(3, 4));
      await tester.pump();
      expect(find.bySemanticsLabel('Insert 3 by 4 table'), findsOne);
      handle.dispose();
    });
  });

  group('toolbar commands', () {
    testWidgets('merge, insert and delete act on the selected cells',
        (tester) async {
      await pump(tester, wideViewport);
      await selectTable(tester);
      final gesture = await tester.startGesture(cellCenter(tester, 0, 0));
      await gesture.moveTo(cellCenter(tester, 1, 1));
      await gesture.up();
      await tester.pump();
      expect(cells.canMerge, isTrue);
      cells.merge();
      await tester.pump();
      expect(table().cell(0, 0).rowSpan, 2);
      expect(cells.canUnmerge, isTrue);
      expect(cellKey(1, 1), findsNothing);
      cells.insertRowAbove();
      await tester.pump();
      expect(table().rowCount, 4);
      expect(cells.range!.top, 1);
      cells.deleteColumns();
      await tester.pump();
      expect(table().columnCount, 1);
      cells.format(const CellFormat(fill: SlideColor(0xFF00FF00)));
      expect(table().fillAt(cells.range!.top, 0), const SlideColor(0xFF00FF00));
      expect(undoAll(doc), 4);
    });
  });
}
