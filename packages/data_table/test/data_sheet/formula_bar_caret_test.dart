import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/gestures.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:material_ui/material_ui.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter_test/flutter_test.dart';

import '../support/sheet.dart';

const _value = '=SUM(A1:A3)+B2';

Finder get _bar => find.byKey(const ValueKey('data_sheet_formula_field'));

TextEditingController _barText(WidgetTester tester) =>
    tester.widget<TextField>(_bar).controller!;

Future<DataSheetController> _pumpSheet(WidgetTester tester, Size size) async {
  setSheetSize(tester, size);
  final controller = sheetOf([
    ['1', '2', _value],
    ['3', '4', '5'],
    ['6', '7', '8'],
  ]);
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

/// The global point between characters `offset - 1` and `offset` of the
/// bar's text, at the middle of the line.
Offset _caretPoint(WidgetTester tester, int offset) {
  final editable = tester
      .state<EditableTextState>(
        find.descendant(of: _bar, matching: find.byType(EditableText)),
      )
      .renderEditable;
  final rect = editable.getLocalRectForCaret(TextPosition(offset: offset));
  return editable.localToGlobal(rect.center);
}

Future<void> _click(WidgetTester tester, Offset point) async {
  await tester.tapAt(point, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [('narrow', narrow), ('wide', wide)]) {
    group('formula bar caret ($name)', () {
      testWidgets('clicking from the grid puts the caret at the click', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(cellAt(0, 2).first);
        await tester.pumpAndSettle();
        expect(_barText(tester).text, _value);

        await _click(tester, _caretPoint(tester, 5));

        expect(controller.selection.activeRow, 0);
        expect(
          _barText(tester).selection,
          const TextSelection.collapsed(offset: 5),
        );
      });

      testWidgets('clicking while editing in the bar moves the caret there', (
        tester,
      ) async {
        await _pumpSheet(tester, size);
        await tester.tap(cellAt(0, 2).first);
        await tester.pumpAndSettle();
        await _click(tester, _caretPoint(tester, 5));
        // Far enough apart to be two clicks rather than a double-click.
        await tester.pump(const Duration(seconds: 1));

        await _click(tester, _caretPoint(tester, 9));

        expect(
          _barText(tester).selection,
          const TextSelection.collapsed(offset: 9),
        );
      });

      testWidgets('clicking the bar while the cell editor is open', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(cellAt(0, 2).first);
        await tester.pump();
        await tester.tap(cellAt(0, 2).first);
        await tester.pumpAndSettle();
        expect(controller.selection.activeRow, 0);

        await _click(tester, _caretPoint(tester, 7));

        expect(controller.selection.activeRow, 0);
        expect(
          _barText(tester).selection,
          const TextSelection.collapsed(offset: 7),
        );
      });

      testWidgets('clicking past the end puts the caret at the end', (
        tester,
      ) async {
        await _pumpSheet(tester, size);
        await tester.tap(cellAt(0, 2).first);
        await tester.pumpAndSettle();

        final end = tester.getTopRight(_bar) + const Offset(-4, 10);
        await _click(tester, end);

        final selection = _barText(tester).selection;
        expect(selection.isCollapsed, isTrue);
        expect(selection.baseOffset, _value.length);
      });
    });
  }
}
