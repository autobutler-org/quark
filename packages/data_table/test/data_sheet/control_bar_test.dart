import 'package:data_table/src/data_sheet/control_bar.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter_test/flutter_test.dart';

DataSheetController _makeController(List<List<String>> values) {
  return DataSheetController.fromTable(
    DataTable(
      values
          .map((row) => DataRow(row.map((v) => DataCell(v)).toList()))
          .toList(),
    ),
  );
}

/// The toolbar has no separate append button, so the insert buttons have to
/// stay usable with nothing selected — otherwise a freshly opened sheet can't
/// be grown until the user clicks a cell.
void main() {
  Future<void> pumpBar(
    WidgetTester tester,
    DataSheetController controller, {
    VoidCallback? onExportXlsx,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DataSheetControlBar(
            controller: controller,
            onExportXlsx: onExportXlsx,
          ),
        ),
      ),
    );
  }

  const exportXlsx = ValueKey('data_sheet_export_xlsx');

  testWidgets('the Excel export shows only when the host handles it', (
    tester,
  ) async {
    final controller = _makeController([
      ['a'],
    ]);
    addTearDown(controller.dispose);

    await pumpBar(tester, controller);
    expect(find.byKey(exportXlsx), findsNothing);

    var exports = 0;
    await pumpBar(tester, controller, onExportXlsx: () => exports++);
    expect(find.byTooltip('Export Excel workbook'), findsOneWidget);
    await tester.ensureVisible(find.byKey(exportXlsx));
    await tester.tap(find.byKey(exportXlsx));
    expect(exports, 1);
  });

  testWidgets('with no selection, row inserts anchor to the sheet edges', (
    tester,
  ) async {
    final controller = _makeController([
      ['a'],
      ['b'],
    ]);
    addTearDown(controller.dispose);

    await pumpBar(tester, controller);
    await tester.tap(find.byTooltip('Add row at end'));
    await tester.pump();

    expect(controller.rowCount, 3);
    expect(controller.cellAt(2, 0).value, '');
    expect(controller.cellAt(1, 0).value, 'b',
        reason: 'appended, not inserted');

    await tester.tap(find.byTooltip('Insert row at top'));
    await tester.pump();

    expect(controller.rowCount, 4);
    expect(controller.cellAt(1, 0).value, 'a');
  });

  testWidgets('with no selection, column inserts anchor to the sheet edges', (
    tester,
  ) async {
    final controller = _makeController([
      ['a', 'b'],
    ]);
    addTearDown(controller.dispose);

    await pumpBar(tester, controller);
    await tester.tap(find.byTooltip('Add column at end'));
    await tester.pump();

    expect(controller.colCount, 3);
    expect(controller.cellAt(0, 1).value, 'b',
        reason: 'appended, not inserted');

    await tester.tap(find.byTooltip('Insert column at left'));
    await tester.pump();

    expect(controller.colCount, 4);
    expect(controller.cellAt(0, 1).value, 'a');
  });

  testWidgets('a selection restores the relative insert behavior', (
    tester,
  ) async {
    final controller = _makeController([
      ['a'],
      ['b'],
      ['c'],
    ]);
    addTearDown(controller.dispose);

    await pumpBar(tester, controller);
    controller.selection.goTo(1, 0);
    await tester.pump();

    await tester.tap(find.byTooltip('Insert row before'));
    await tester.pump();

    expect(controller.rowCount, 4);
    expect(controller.cellAt(1, 0).value, '', reason: 'inserted above row "b"');
    expect(controller.cellAt(2, 0).value, 'b');
  });

  testWidgets('column inserts stay disabled while the sheet has no rows', (
    tester,
  ) async {
    final controller = _makeController([]);
    addTearDown(controller.dispose);

    await pumpBar(tester, controller);

    // insertColumnAt is a no-op without a row to hold the cells.
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byTooltip('Add column at end'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    // Rows can still be added, which is what makes the sheet recoverable.
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byTooltip('Add row at end'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });
}
