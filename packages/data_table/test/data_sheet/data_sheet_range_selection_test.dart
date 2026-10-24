import 'package:data_table/src/data_sheet/cell/cell.dart';
import 'package:data_table/src/data_sheet/data_sheet.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter/gestures.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sheet.dart';

DataSheetController _makeController({int rows = 30, int cols = 5}) {
  return DataSheetController.fromTable(gridTable(rows, cols));
}

Future<DataSheetController> _pumpSheet(WidgetTester tester, Size size) async {
  setSheetSize(tester, size);
  final controller = _makeController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DataSheet(controller: controller, table: DataTable([])),
      ),
    ),
  );
  return controller;
}

String _nameBox(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('data_sheet_name_box')))
    .data!;

Future<void> _shiftKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  for (final (name, size) in [('narrow', narrow), ('wide', wide)]) {
    group('range selection ($name)', () {
      testWidgets('a single tap still highlights one cell', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(cellAt(1, 1));
        await tester.pump();

        expect(controller.selection.highlightedRow, 1);
        expect(controller.selection.hasRange, false);
        expect(_nameBox(tester), 'B2');
      });

      testWidgets('Shift+arrows extend the range and arrows collapse it', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(cellAt(1, 1));
        await tester.pump();

        await _shiftKey(tester, LogicalKeyboardKey.arrowDown);
        await _shiftKey(tester, LogicalKeyboardKey.arrowDown);
        await _shiftKey(tester, LogicalKeyboardKey.arrowRight);

        expect(_nameBox(tester), 'B2:C4');
        expect(controller.selection.highlightedRow, 1);
        expect(controller.selection.highlightedCol, 1);

        await _shiftKey(tester, LogicalKeyboardKey.arrowUp);
        expect(_nameBox(tester), 'B2:C3');

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(controller.selection.hasRange, false);
        expect(_nameBox(tester), 'B3');
      });

      testWidgets('Shift+arrow stops at the sheet edge', (tester) async {
        await _pumpSheet(tester, size);
        await tester.tap(cellAt(0, 0));
        await tester.pump();

        await _shiftKey(tester, LogicalKeyboardKey.arrowUp);
        await _shiftKey(tester, LogicalKeyboardKey.arrowLeft);
        expect(_nameBox(tester), 'A1');
      });

      testWidgets('Shift+click extends from the highlighted cell', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(cellAt(3, 2));
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(cellAt(1, 0));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(_nameBox(tester), 'A2:C4');
        expect(controller.selection.hasActiveCell, false);
      });

      testWidgets('range cells are tinted and the anchor is not', (
        tester,
      ) async {
        await _pumpSheet(tester, size);
        await tester.tap(cellAt(1, 1));
        await tester.pump();
        await _shiftKey(tester, LogicalKeyboardKey.arrowDown);
        await _shiftKey(tester, LogicalKeyboardKey.arrowRight);

        Cell cellWidget(int r, int c) => tester.widget<Cell>(cellAt(r, c));
        expect(cellWidget(2, 2).isInRange, true);
        expect(cellWidget(3, 3).isInRange, false);

        final primary = Theme.of(
          tester.element(cellAt(1, 1)),
        ).colorScheme.primary.withValues(alpha: kRangeTintAlpha);
        BoxDecoration decorationAt(int r, int c) =>
            tester
                    .widget<Container>(
                      find.descendant(
                        of: cellAt(r, c),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(decorationAt(2, 2).color, primary);
        expect(decorationAt(1, 1).color, isNull);
        expect(decorationAt(3, 3).color, isNull);
      });

      testWidgets('a mouse drag selects the cells it crosses', (tester) async {
        final controller = await _pumpSheet(tester, size);
        final gesture = await tester.startGesture(
          tester.getCenter(cellAt(1, 0)),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(tester.getCenter(cellAt(2, 1)));
        await gesture.moveTo(tester.getCenter(cellAt(4, 2)));
        await gesture.up();
        await tester.pump();

        expect(_nameBox(tester), 'A2:C5');
        expect(controller.selection.highlightedRow, 1);
        expect(controller.selection.highlightedCol, 0);
      });

      testWidgets('a long-press drag on touch selects a range', (tester) async {
        await _pumpSheet(tester, size);
        final gesture = await tester.startGesture(
          tester.getCenter(cellAt(1, 0)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveTo(tester.getCenter(cellAt(2, 1)));
        await gesture.moveTo(tester.getCenter(cellAt(3, 2)));
        await gesture.up();
        await tester.pump();

        expect(_nameBox(tester), 'A2:C4');
      });

      testWidgets('a touch swipe scrolls instead of selecting', (tester) async {
        final controller = await _pumpSheet(tester, size);
        final before = tester.getTopLeft(cellAt(5, 0)).dy;

        await tester.dragFrom(
          tester.getCenter(cellAt(8, 0)),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        expect(tester.getTopLeft(cellAt(5, 0)).dy, lessThan(before));
        expect(controller.selection.hasRange, false);
      });

      testWidgets('a column header click selects the whole column', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(find.byKey(const ValueKey('col_header_1')));
        await tester.pump();

        expect(_nameBox(tester), 'B1:B30');
        expect(controller.selection.highlightedRow, 0);
        expect(controller.selection.highlightedCol, 1);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(find.byKey(const ValueKey('col_header_2')));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(_nameBox(tester), 'B1:C30');
      });

      testWidgets('a row header click selects the whole row', (tester) async {
        await _pumpSheet(tester, size);
        await tester.tap(find.byKey(const ValueKey('row_num_2')));
        await tester.pump();
        expect(_nameBox(tester), 'A3:E3');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(find.byKey(const ValueKey('row_num_4')));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(_nameBox(tester), 'A3:E5');
      });

      testWidgets('a header click commits a pending edit', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(cellAt(0, 0));
        await tester.pump();
        await tester.tap(cellAt(0, 0));
        await tester.pump();
        expect(controller.selection.hasActiveCell, true);
        await tester.enterText(find.byType(TextField).last, 'edited');

        await tester.tap(find.byKey(const ValueKey('row_num_3')));
        await tester.pump();

        expect(controller.cellAt(0, 0).value, 'edited');
        expect(_nameBox(tester), 'A4:E4');
      });

      testWidgets('Ctrl+A selects every cell', (tester) async {
        await _pumpSheet(tester, size);
        await tester.tap(cellAt(2, 2));
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(_nameBox(tester), 'A1:E30');
      });
    });
  }
}
