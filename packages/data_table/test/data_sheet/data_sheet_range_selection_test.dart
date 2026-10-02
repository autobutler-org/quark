import 'package:data_table/src/data_sheet/cell/cell.dart';
import 'package:data_table/src/data_sheet/data_sheet.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter/gestures.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrow = Size(360, 640);
const _wide = Size(1280, 800);

DataSheetController _makeController({int rows = 30, int cols = 5}) {
  return DataSheetController.fromTable(
    DataTable(
      List.generate(
        rows,
        (r) => DataRow(List.generate(cols, (c) => DataCell('$r,$c'))),
      ),
    ),
  );
}

Future<DataSheetController> _pumpSheet(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

Finder _cell(int r, int c) => find.byKey(ValueKey('r${r}c$c'));

String _nameBox(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('data_sheet_name_box')))
    .data!;

Future<void> _shiftKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

Future<void> _ctrlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// Highlights B2 and extends the range to C3.
Future<void> _selectB2toC3(WidgetTester tester) async {
  await tester.tap(_cell(1, 1));
  await tester.pump();
  await _shiftKey(tester, LogicalKeyboardKey.arrowRight);
  await _shiftKey(tester, LogicalKeyboardKey.arrowDown);
}

void main() {
  for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
    group('range selection ($name)', () {
      testWidgets('a single tap still highlights one cell', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(_cell(1, 1));
        await tester.pump();

        expect(controller.selection.highlightedRow, 1);
        expect(controller.selection.hasRange, false);
        expect(_nameBox(tester), 'B2');
      });

      testWidgets('Shift+arrows extend the range and arrows collapse it', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(_cell(1, 1));
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
        await tester.tap(_cell(0, 0));
        await tester.pump();

        await _shiftKey(tester, LogicalKeyboardKey.arrowUp);
        await _shiftKey(tester, LogicalKeyboardKey.arrowLeft);
        expect(_nameBox(tester), 'A1');
      });

      testWidgets('Shift+click extends from the highlighted cell', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(_cell(3, 2));
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(_cell(1, 0));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(_nameBox(tester), 'A2:C4');
        expect(controller.selection.hasActiveCell, false);
      });

      testWidgets('range cells are tinted and the anchor is not', (
        tester,
      ) async {
        await _pumpSheet(tester, size);
        await tester.tap(_cell(1, 1));
        await tester.pump();
        await _shiftKey(tester, LogicalKeyboardKey.arrowDown);
        await _shiftKey(tester, LogicalKeyboardKey.arrowRight);

        Cell cellAt(int r, int c) => tester.widget<Cell>(_cell(r, c));
        expect(cellAt(2, 2).isInRange, true);
        expect(cellAt(3, 3).isInRange, false);

        final primary = Theme.of(tester.element(_cell(1, 1)))
            .colorScheme
            .primary
            .withValues(alpha: kRangeTintAlpha);
        BoxDecoration decorationAt(int r, int c) => tester
            .widget<Container>(
              find.descendant(
                of: _cell(r, c),
                matching: find.byType(Container),
              ),
            )
            .decoration! as BoxDecoration;
        expect(decorationAt(2, 2).color, primary);
        expect(decorationAt(1, 1).color, isNull);
        expect(decorationAt(3, 3).color, isNull);
      });

      testWidgets('a mouse drag selects the cells it crosses', (tester) async {
        final controller = await _pumpSheet(tester, size);
        final gesture = await tester.startGesture(
          tester.getCenter(_cell(1, 0)),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(tester.getCenter(_cell(2, 1)));
        await gesture.moveTo(tester.getCenter(_cell(4, 2)));
        await gesture.up();
        await tester.pump();

        expect(_nameBox(tester), 'A2:C5');
        expect(controller.selection.highlightedRow, 1);
        expect(controller.selection.highlightedCol, 0);
      });

      testWidgets('a long-press drag on touch selects a range', (
        tester,
      ) async {
        await _pumpSheet(tester, size);
        final gesture = await tester.startGesture(
          tester.getCenter(_cell(1, 0)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveTo(tester.getCenter(_cell(2, 1)));
        await gesture.moveTo(tester.getCenter(_cell(3, 2)));
        await gesture.up();
        await tester.pump();

        expect(_nameBox(tester), 'A2:C4');
      });

      testWidgets('a touch swipe scrolls instead of selecting', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        final before = tester.getTopLeft(_cell(5, 0)).dy;

        await tester.dragFrom(
          tester.getCenter(_cell(8, 0)),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        expect(tester.getTopLeft(_cell(5, 0)).dy, lessThan(before));
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
        await tester.tap(_cell(0, 0));
        await tester.pump();
        await tester.tap(_cell(0, 0));
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
        await tester.tap(_cell(2, 2));
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(_nameBox(tester), 'A1:E30');
      });
    });

    group('range operations ($name)', () {
      String at(DataSheetController c, int r, int col) =>
          c.cellAt(r, col).value;

      testWidgets('Delete clears every cell in the range, undone at once',
          (tester) async {
        final c = await _pumpSheet(tester, size);
        await _selectB2toC3(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();
        expect(
          [at(c, 1, 1), at(c, 1, 2), at(c, 2, 1), at(c, 2, 2)],
          ['', '', '', ''],
        );
        expect(at(c, 1, 3), '1,3');

        await _ctrlKey(tester, LogicalKeyboardKey.keyZ);
        expect([at(c, 1, 1), at(c, 2, 2)], ['1,1', '2,2']);
      });

      testWidgets('copy then paste lands the block at the new cell',
          (tester) async {
        final c = await _pumpSheet(tester, size);
        await _selectB2toC3(tester);
        await _ctrlKey(tester, LogicalKeyboardKey.keyC);

        await tester.tap(_cell(5, 0));
        await tester.pump();
        await _ctrlKey(tester, LogicalKeyboardKey.keyV);

        expect(
          [at(c, 5, 0), at(c, 5, 1), at(c, 6, 0), at(c, 6, 1)],
          ['1,1', '1,2', '2,1', '2,2'],
        );
        expect(at(c, 5, 2), '5,2');
      });

      testWidgets('cut clears the range and pastes elsewhere', (tester) async {
        final c = await _pumpSheet(tester, size);
        await _selectB2toC3(tester);
        await _ctrlKey(tester, LogicalKeyboardKey.keyX);
        expect(at(c, 1, 1), '');

        await tester.tap(_cell(4, 0));
        await tester.pump();
        await _ctrlKey(tester, LogicalKeyboardKey.keyV);
        expect([at(c, 4, 0), at(c, 5, 1)], ['1,1', '2,2']);
      });

      testWidgets('one copied cell pasted over a range fills it',
          (tester) async {
        final c = await _pumpSheet(tester, size);
        await tester.tap(_cell(0, 0));
        await tester.pump();
        await _ctrlKey(tester, LogicalKeyboardKey.keyC);

        await _selectB2toC3(tester);
        await _ctrlKey(tester, LogicalKeyboardKey.keyV);
        expect(
          [at(c, 1, 1), at(c, 1, 2), at(c, 2, 1), at(c, 2, 2)],
          ['0,0', '0,0', '0,0', '0,0'],
        );
      });
    });
  }
}
