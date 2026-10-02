import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

DataTable _table(int rows, int cols) => DataTable(
      List.generate(
        rows,
        (r) => DataRow(List.generate(cols, (c) => DataCell('$r,$c'))),
      ),
    );

/// #2691: pixel sizes, auto-fit and frozen panes on the controller, and the
/// layout keys a `.qsheet` tab saves them under.
void main() {
  group('fromTable normalizes saved sizes', () {
    test('pads missing widths and heights with the defaults', () {
      final c = DataSheetController.fromTable(
        _table(3, 3),
        columnWidths: [150],
        rowHeights: [60, 30],
      );
      addTearDown(c.dispose);
      expect(c.columnWidths, [150.0, 100.0, 100.0]);
      expect(c.rowHeights, [60.0, 30.0, 40.0]);
    });

    test('drops sizes past the last column and row', () {
      final c = DataSheetController.fromTable(
        _table(1, 2),
        columnWidths: [120, 80, 90, 70],
        rowHeights: [50, 50, 50],
      );
      addTearDown(c.dispose);
      expect(c.columnWidths, [120.0, 80.0]);
      expect(c.rowHeights, [50.0]);
    });

    test('replaces unusable sizes with the default or the minimum', () {
      final c = DataSheetController.fromTable(
        _table(2, 3),
        columnWidths: [double.nan, 2, double.infinity],
        rowHeights: [-5, double.nan],
      );
      addTearDown(c.dispose);
      expect(c.columnWidths, [100.0, 24.0, 100.0]);
      expect(c.rowHeights, [24.0, 40.0]);
    });

    test('migrates flex factors to pixel widths', () {
      final c = DataSheetController.fromTable(
        _table(1, 3),
        columnFlex: [1, 2, 3],
      );
      addTearDown(c.dispose);
      expect(c.columnWidths, [100.0, 200.0, 300.0]);
    });

    test('pixel widths win over flex factors', () {
      final c = DataSheetController.fromTable(
        _table(1, 2),
        columnWidths: [70, 80],
        columnFlex: [3, 3],
      );
      addTearDown(c.dispose);
      expect(c.columnWidths, [70.0, 80.0]);
    });
  });

  group('fromLayoutJson', () {
    test('a tab saved before sizes existed loads with defaults', () {
      final c = DataSheetController.fromLayoutJson(_table(2, 2), {
        'name': 'Sheet 1',
        'data': {'rows': []},
      });
      addTearDown(c.dispose);
      expect(c.columnWidths, [100.0, 100.0]);
      expect(c.rowHeights, [40.0, 40.0]);
      expect(c.frozenRows, 0);
      expect(c.frozenColumns, 0);
    });

    test('a tab saved before freezing existed keeps its sizes', () {
      final c = DataSheetController.fromLayoutJson(_table(2, 2), {
        'columnWidths': [120, 90.5],
        'rowHeights': [30, 50],
      });
      addTearDown(c.dispose);
      expect(c.columnWidths, [120.0, 90.5]);
      expect(c.rowHeights, [30.0, 50.0]);
      expect(c.frozenRows, 0);
    });

    test('a legacy columnFlex key becomes pixel widths', () {
      final c = DataSheetController.fromLayoutJson(_table(1, 2), {
        'columnFlex': [2, 1],
      });
      addTearDown(c.dispose);
      expect(c.columnWidths, [200.0, 100.0]);
    });

    test('malformed values fall back instead of throwing', () {
      final c = DataSheetController.fromLayoutJson(_table(2, 2), {
        'columnWidths': 'wide',
        'rowHeights': [null, 'tall'],
        'frozenRows': '1',
        'frozenColumns': 9,
      });
      addTearDown(c.dispose);
      expect(c.columnWidths, [100.0, 100.0]);
      expect(c.rowHeights, [40.0, 40.0]);
      expect(c.frozenRows, 0);
      expect(c.frozenColumns, 2, reason: 'clamped to the column count');
    });

    test('round-trips through layoutToJson', () {
      final a = DataSheetController.fromTable(_table(4, 3))
        ..setColumnWidth(1, 180)
        ..setRowHeight(2, 64)
        ..setFrozenRows(1)
        ..setFrozenColumns(2);
      addTearDown(a.dispose);
      final json = a.layoutToJson();
      expect(json['frozenRows'], 1);
      expect(json['frozenColumns'], 2);

      final b = DataSheetController.fromLayoutJson(_table(4, 3), json);
      addTearDown(b.dispose);
      expect(b.columnWidths, a.columnWidths);
      expect(b.rowHeights, a.rowHeights);
      expect(b.frozenRows, 1);
      expect(b.frozenColumns, 2);
    });
  });

  group('freeze', () {
    test('clamps to the sheet and notifies', () {
      final c = DataSheetController.fromTable(_table(3, 2));
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.setFrozenRows(10);
      c.setFrozenColumns(-1);

      expect(c.frozenRows, 3);
      expect(c.frozenColumns, 0);
      expect(notified, 1, reason: 'an unchanged count does not notify');
    });

    test('can be undone', () {
      final c = DataSheetController.fromTable(_table(3, 2))..setFrozenRows(1);
      addTearDown(c.dispose);
      c.undo();
      expect(c.frozenRows, 0);
      c.redo();
      expect(c.frozenRows, 1);
    });

    test('rows inserted or deleted inside the frozen band move its edge', () {
      final c = DataSheetController.fromTable(_table(5, 2))..setFrozenRows(2);
      addTearDown(c.dispose);

      c.insertRowAt(1);
      expect(c.frozenRows, 3);
      c.insertRowAt(3);
      expect(c.frozenRows, 3, reason: 'inserted below the band');
      c.duplicateRow(0);
      expect(c.frozenRows, 4);
      c.deleteRowAt(0);
      expect(c.frozenRows, 3);
      c.deleteRowAt(4);
      expect(c.frozenRows, 3, reason: 'deleted below the band');
    });

    test('columns inserted or deleted inside the frozen band move its edge',
        () {
      final c = DataSheetController.fromTable(_table(2, 4))
        ..setFrozenColumns(1);
      addTearDown(c.dispose);

      c.insertColumnAt(0);
      expect(c.frozenColumns, 2);
      c.duplicateColumn(1);
      expect(c.frozenColumns, 3);
      c.deleteColumnAt(2);
      expect(c.frozenColumns, 2);
      c.insertColumnAt(3);
      expect(c.frozenColumns, 2, reason: 'inserted right of the band');
    });

    test('a CSV import keeps the freeze inside the new sheet', () {
      final c = DataSheetController.fromTable(_table(5, 5))
        ..setFrozenRows(4)
        ..setFrozenColumns(4);
      addTearDown(c.dispose);
      c.loadFromCsv('a,b\nc,d');
      expect(c.frozenRows, 2);
      expect(c.frozenColumns, 2);
    });
  });

  group('resize and auto-fit undo', () {
    test('a drag is one undo step however many updates it sends', () {
      final c = DataSheetController.fromTable(_table(1, 2));
      addTearDown(c.dispose);

      c.beginResize();
      c.setColumnWidth(0, 110);
      c.setColumnWidth(0, 130);
      c.setColumnWidth(0, 160);
      expect(c.canUndo, true);

      c.undo();
      expect(c.columnWidths[0], 100.0);
      expect(c.canUndo, false);
    });

    test('auto-fit can be undone', () {
      final c = DataSheetController.fromTable(
        DataTable([
          DataRow([DataCell('a much longer value than fits in 100px')]),
        ]),
      );
      addTearDown(c.dispose);

      c.autoSizeColumn(0);
      expect(c.columnWidths[0], greaterThan(100));
      c.undo();
      expect(c.columnWidths[0], 100.0);

      c.autoSizeRow(0);
      c.undo();
      expect(c.rowHeights[0], 40.0);
    });
  });
}
