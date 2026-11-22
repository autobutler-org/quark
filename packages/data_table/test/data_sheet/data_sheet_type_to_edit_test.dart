import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:data_table/src/data_sheet/cell/editable_cell.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:material_ui/material_ui.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sheet.dart';

Finder get _cellEditor => find.descendant(
  of: find.byType(EditableCell),
  matching: find.byType(TextField),
);

/// Pumps a sheet over `old` cells with (0, 0) highlighted, not editing.
Future<DataSheetController> _pumpHighlighted(WidgetTester tester) async {
  setSheetSize(tester, wide);
  final controller = sheetOf([
    ['old', 'b'],
    ['c', 'd'],
  ]);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DataSheet(controller: controller, table: DataTable([])),
      ),
    ),
  );
  await tester.tap(cellAt(0, 0).first);
  await tester.pump();
  expect(controller.selection.highlightedRow, 0);
  expect(controller.selection.hasActiveCell, isFalse);
  return controller;
}

void main() {
  testWidgets('typing on a highlighted cell keeps the first character', (
    tester,
  ) async {
    final controller = await _pumpHighlighted(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();

    final editor = tester.widget<TextField>(_cellEditor).controller!;
    expect(editor.text, 'h');
    expect(editor.selection, const TextSelection.collapsed(offset: 1));

    // The platform appends the next character to the focused editor.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'hi',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.cellAt(0, 0).value, 'hi');
  });

  testWidgets('Escape after typing restores the old value', (tester) async {
    final controller = await _pumpHighlighted(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(controller.cellAt(0, 0).value, 'old');
  });

  testWidgets('arrows on a highlighted cell move without editing', (
    tester,
  ) async {
    final controller = await _pumpHighlighted(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controller.selection.highlightedRow, 1);
    expect(controller.selection.hasActiveCell, isFalse);
    expect(controller.cellAt(0, 0).value, 'old');
  });

  testWidgets('a Ctrl combination does not type into the cell', (tester) async {
    final controller = await _pumpHighlighted(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('q'), findsNothing);
    expect(controller.cellAt(0, 0).value, 'old');
  });
}
