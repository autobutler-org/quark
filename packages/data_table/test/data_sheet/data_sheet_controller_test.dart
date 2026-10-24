import 'package:data_table/src/data_sheet/cell_range.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sheet.dart';

List<List<String>> _values(DataSheetController c) => [
  for (var r = 0; r < c.rowCount; r++)
    [for (var col = 0; col < c.colCount; col++) c.cellAt(r, col).value],
];

/// A 3x3 sheet of `a`..`i`, row by row.
DataSheetController _grid() => sheetOf([
  ['a', 'b', 'c'],
  ['d', 'e', 'f'],
  ['g', 'h', 'i'],
]);

void main() {
  group('DataSheetController', () {
    group('updateCell', () {
      test('updates cell value', () {
        final c = sheetOf([
          ['old', 'b'],
        ]);
        c.updateCell(0, 0, DataCell('new'));
        expect(c.cellAt(0, 0).value, 'new');
        c.dispose();
      });

      test('notifies listeners', () {
        final c = sheetOf([
          ['a'],
        ]);
        var notified = false;
        c.addListener(() => notified = true);
        c.updateCell(0, 0, DataCell('b'));
        expect(notified, true);
        c.dispose();
      });
    });

    group('clearCell', () {
      test('clears a single cell value', () {
        final c = sheetOf([
          ['hello', 'world'],
        ]);
        c.clearCell(0, 0);
        expect(c.cellAt(0, 0).value, '');
        expect(c.cellAt(0, 1).value, 'world');
        c.dispose();
      });

      test('does nothing for out-of-bounds indices', () {
        final c = sheetOf([
          ['a'],
        ]);
        expect(() => c.clearCell(5, 5), returnsNormally);
        c.dispose();
      });
    });

    group('clearRow', () {
      test('clears all cells in the row', () {
        final c = sheetOf([
          ['a', 'b', 'c'],
          ['d', 'e', 'f'],
        ]);
        c.clearRow(0);
        expect(c.cellAt(0, 0).value, '');
        expect(c.cellAt(0, 1).value, '');
        expect(c.cellAt(0, 2).value, '');
        expect(c.cellAt(1, 0).value, 'd');
        c.dispose();
      });
    });

    group('clearColumn', () {
      test('clears all cells in the column', () {
        final c = sheetOf([
          ['a', 'b'],
          ['c', 'd'],
        ]);
        c.clearColumn(1);
        expect(c.cellAt(0, 1).value, '');
        expect(c.cellAt(1, 1).value, '');
        expect(c.cellAt(0, 0).value, 'a');
        c.dispose();
      });
    });

    group('addRow', () {
      test('appends an empty row', () {
        final c = sheetOf([
          ['a', 'b'],
        ]);
        c.addRow();
        expect(c.rowCount, 2);
        expect(c.cellAt(1, 0).value, '');
        expect(c.cellAt(1, 1).value, '');
        c.dispose();
      });
    });

    group('insertRowAt', () {
      test('inserts at the given index', () {
        final c = sheetOf([
          ['a'],
          ['c'],
        ]);
        c.insertRowAt(1, cells: [DataCell('b')]);
        expect(c.rowCount, 3);
        expect(c.cellAt(1, 0).value, 'b');
        expect(c.cellAt(2, 0).value, 'c');
        c.dispose();
      });

      test('clamps to end when index exceeds rowCount', () {
        final c = sheetOf([
          ['a'],
        ]);
        c.insertRowAt(99);
        expect(c.rowCount, 2);
        c.dispose();
      });
    });

    group('deleteRowAt', () {
      test('removes the row at index', () {
        final c = sheetOf([
          ['a'],
          ['b'],
          ['c'],
        ]);
        c.deleteRowAt(1);
        expect(c.rowCount, 2);
        expect(c.cellAt(0, 0).value, 'a');
        expect(c.cellAt(1, 0).value, 'c');
        c.dispose();
      });

      test('does nothing for out-of-bounds index', () {
        final c = sheetOf([
          ['a'],
        ]);
        expect(() => c.deleteRowAt(5), returnsNormally);
        expect(c.rowCount, 1);
        c.dispose();
      });
    });

    group('duplicateRow', () {
      test('inserts copy immediately after source', () {
        final c = sheetOf([
          ['x', 'y'],
          ['z', 'w'],
        ]);
        c.duplicateRow(0);
        expect(c.rowCount, 3);
        expect(c.cellAt(1, 0).value, 'x');
        expect(c.cellAt(1, 1).value, 'y');
        expect(c.cellAt(2, 0).value, 'z');
        c.dispose();
      });
    });

    group('addColumn', () {
      test('appends an empty column to all rows', () {
        final c = sheetOf([
          ['a', 'b'],
          ['c', 'd'],
        ]);
        c.addColumn();
        expect(c.colCount, 3);
        expect(c.cellAt(0, 2).value, '');
        expect(c.cellAt(1, 2).value, '');
        c.dispose();
      });

      test('grows columnWidths on addColumn', () {
        final c = sheetOf([
          ['a'],
        ]);
        c.addColumn();
        expect(c.columnWidths.length, 2);
        c.dispose();
      });
    });

    group('deleteColumnAt', () {
      test('removes the column at index', () {
        final c = sheetOf([
          ['a', 'b', 'c'],
        ]);
        c.deleteColumnAt(1);
        expect(c.colCount, 2);
        expect(c.cellAt(0, 0).value, 'a');
        expect(c.cellAt(0, 1).value, 'c');
        c.dispose();
      });
    });

    group('duplicateColumn', () {
      test('inserts copy immediately after source', () {
        final c = sheetOf([
          ['x', 'y'],
        ]);
        c.duplicateColumn(0);
        expect(c.colCount, 3);
        expect(c.cellAt(0, 1).value, 'x');
        expect(c.cellAt(0, 2).value, 'y');
        c.dispose();
      });
    });

    group('rowHeights', () {
      test('addRow appends a new rowHeight', () {
        final c = sheetOf([
          ['a'],
        ]);
        c.addRow();
        expect(c.rowHeights.length, 2);
        c.dispose();
      });

      test('insertRowAt inserts a rowHeight at the correct index', () {
        final c = sheetOf([
          ['a'],
          ['b'],
        ]);
        c.setRowHeight(1, 60.0);
        c.insertRowAt(1);
        expect(c.rowHeights[1], 40.0); // new default
        expect(c.rowHeights[2], 60.0); // previous row 1 shifted down
        c.dispose();
      });

      test('deleteRowAt removes the corresponding rowHeight', () {
        final c = sheetOf([
          ['a'],
          ['b'],
          ['c'],
        ]);
        c.setRowHeight(1, 80.0);
        c.deleteRowAt(0);
        expect(c.rowHeights.length, 2);
        expect(c.rowHeights[0], 80.0);
        c.dispose();
      });

      test('duplicateRow copies the source rowHeight', () {
        final c = sheetOf([
          ['a'],
          ['b'],
        ]);
        c.setRowHeight(0, 55.0);
        c.duplicateRow(0);
        expect(c.rowHeights[1], 55.0);
        c.dispose();
      });
    });

    group('setColumnWidth', () {
      test('updates the width at the given index', () {
        final c = sheetOf([
          ['a', 'b'],
        ]);
        c.setColumnWidth(0, 150.0);
        expect(c.columnWidths[0], 150.0);
        c.dispose();
      });

      test('clamps to kMinColumnWidth', () {
        final c = sheetOf([
          ['a'],
        ]);
        c.setColumnWidth(0, 0.0);
        expect(c.columnWidths[0], 24.0);
        c.dispose();
      });

      test('does nothing for out-of-range index', () {
        final c = sheetOf([
          ['a'],
        ]);
        expect(() => c.setColumnWidth(5, 100.0), returnsNormally);
        c.dispose();
      });
    });

    group('setRowHeight', () {
      test('updates the height at the given index', () {
        final c = sheetOf([
          ['a'],
          ['b'],
        ]);
        c.setRowHeight(1, 60.0);
        expect(c.rowHeights[1], 60.0);
        c.dispose();
      });

      test('clamps to kMinRowHeight', () {
        final c = sheetOf([
          ['a'],
        ]);
        c.setRowHeight(0, 0.0);
        expect(c.rowHeights[0], 24.0);
        c.dispose();
      });
    });

    group('autoSizeColumn', () {
      test('sets width >= kMinColumnWidth for non-empty column', () {
        final c = sheetOf([
          ['Hello World'],
          ['Short'],
        ]);
        c.autoSizeColumn(0);
        expect(c.columnWidths[0], greaterThanOrEqualTo(24.0));
        c.dispose();
      });

      test('does nothing for out-of-range column', () {
        final c = sheetOf([
          ['a'],
        ]);
        expect(() => c.autoSizeColumn(5), returnsNormally);
        c.dispose();
      });
    });

    group('autoSizeRow', () {
      test('sets height >= kMinRowHeight', () {
        final c = sheetOf([
          ['Hello World'],
        ]);
        c.autoSizeRow(0);
        expect(c.rowHeights[0], greaterThanOrEqualTo(24.0));
        c.dispose();
      });

      test('does nothing for out-of-range row', () {
        final c = sheetOf([
          ['a'],
        ]);
        expect(() => c.autoSizeRow(5), returnsNormally);
        c.dispose();
      });
    });

    group('sortByColumn', () {
      test('sorts lexicographically ascending', () {
        final c = sheetOf([
          ['banana'],
          ['apple'],
          ['cherry'],
        ]);
        c.sortByColumn(0);
        expect(c.cellAt(0, 0).value, 'apple');
        expect(c.cellAt(1, 0).value, 'banana');
        expect(c.cellAt(2, 0).value, 'cherry');
        c.dispose();
      });

      test('sorts descending', () {
        final c = sheetOf([
          ['1'],
          ['3'],
          ['2'],
        ]);
        c.sortByColumn(0, ascending: false);
        expect(c.cellAt(0, 0).value, '3');
        expect(c.cellAt(1, 0).value, '2');
        expect(c.cellAt(2, 0).value, '1');
        c.dispose();
      });

      test('sorts numerically when values are numbers', () {
        final c = sheetOf([
          ['10'],
          ['9'],
          ['100'],
        ]);
        c.sortByColumn(0);
        expect(c.cellAt(0, 0).value, '9');
        expect(c.cellAt(1, 0).value, '10');
        expect(c.cellAt(2, 0).value, '100');
        c.dispose();
      });
    });

    group('removeDuplicateRows', () {
      test('removes exact duplicates, keeping first occurrence', () {
        final c = sheetOf([
          ['a', 'b'],
          ['c', 'd'],
          ['a', 'b'],
        ]);
        c.removeDuplicateRows();
        expect(c.rowCount, 2);
        expect(c.cellAt(0, 0).value, 'a');
        expect(c.cellAt(1, 0).value, 'c');
        c.dispose();
      });

      test('does nothing when there are no duplicates', () {
        final c = sheetOf([
          ['a'],
          ['b'],
        ]);
        c.removeDuplicateRows();
        expect(c.rowCount, 2);
        c.dispose();
      });
    });

    group('fillDown', () {
      test('fills source value to all rows below', () {
        final c = sheetOf([
          ['src', 'x'],
          ['', 'y'],
          ['', 'z'],
        ]);
        c.fillDown(0, 0);
        expect(c.cellAt(1, 0).value, 'src');
        expect(c.cellAt(2, 0).value, 'src');
        expect(c.cellAt(0, 1).value, 'x');
        c.dispose();
      });
    });

    group('fillRight', () {
      test('fills source value to all columns to the right', () {
        final c = sheetOf([
          ['src', '', ''],
        ]);
        c.fillRight(0, 0);
        expect(c.cellAt(0, 1).value, 'src');
        expect(c.cellAt(0, 2).value, 'src');
        c.dispose();
      });
    });

    group('findCells', () {
      test('returns matching cell positions', () {
        final c = sheetOf([
          ['hello', 'world'],
          ['foo', 'hello'],
        ]);
        final results = c.findCells('hello');
        expect(results.length, 2);
        expect(results[0], (row: 0, col: 0));
        expect(results[1], (row: 1, col: 1));
        c.dispose();
      });

      test('is case-insensitive by default', () {
        final c = sheetOf([
          ['Hello'],
        ]);
        expect(c.findCells('hello').length, 1);
        c.dispose();
      });

      test('is case-sensitive when requested', () {
        final c = sheetOf([
          ['Hello'],
        ]);
        expect(c.findCells('hello', caseSensitive: true).length, 0);
        c.dispose();
      });

      test('returns empty list when no match', () {
        final c = sheetOf([
          ['abc'],
        ]);
        expect(c.findCells('xyz'), isEmpty);
        c.dispose();
      });
    });

    group('replaceCells', () {
      test('replaces all occurrences and returns count', () {
        final c = sheetOf([
          ['foo', 'foobar'],
          ['baz', 'foo'],
        ]);
        final count = c.replaceCells('foo', 'qux');
        expect(count, 3);
        expect(c.cellAt(0, 0).value, 'qux');
        expect(c.cellAt(0, 1).value, 'quxbar');
        expect(c.cellAt(1, 1).value, 'qux');
        c.dispose();
      });

      test('returns 0 and does not modify when from is empty', () {
        final c = sheetOf([
          ['abc'],
        ]);
        final count = c.replaceCells('', 'x');
        expect(count, 0);
        expect(c.cellAt(0, 0).value, 'abc');
        c.dispose();
      });
    });

    group('undo / redo', () {
      test('canUndo is false initially', () {
        final c = sheetOf([
          ['a'],
        ]);
        expect(c.canUndo, false);
        c.dispose();
      });

      test('canUndo becomes true after a mutating operation', () {
        final c = sheetOf([
          ['a'],
        ]);
        c.clearCell(0, 0);
        expect(c.canUndo, true);
        c.dispose();
      });

      test('undo reverses last change', () {
        final c = sheetOf([
          ['original'],
        ]);
        c.clearCell(0, 0);
        c.undo();
        expect(c.cellAt(0, 0).value, 'original');
        c.dispose();
      });

      test('redo reapplies undone change', () {
        final c = sheetOf([
          ['original'],
        ]);
        c.clearCell(0, 0);
        c.undo();
        c.redo();
        expect(c.cellAt(0, 0).value, '');
        c.dispose();
      });

      test('redo stack is cleared after a new mutation', () {
        final c = sheetOf([
          ['a'],
        ]);
        c.clearCell(0, 0);
        c.undo();
        c.clearCell(0, 0);
        expect(c.canRedo, false);
        c.dispose();
      });
    });

    group('range operations', () {
      const topLeft = CellRange(top: 0, left: 0, bottom: 1, right: 1);

      test('valuesIn reads the range row by row', () {
        final c = _grid();
        expect(c.valuesIn(topLeft), [
          ['a', 'b'],
          ['d', 'e'],
        ]);
        c.dispose();
      });

      test('deleteRowAt with a count removes the rows in one undo step', () {
        final c = _grid();
        c.selection.selectRange(2, 0, 1, 0);
        c.deleteRowAt(1, count: 2);
        expect(_values(c), [
          ['a', 'b', 'c'],
        ]);
        // The selection is collapsed onto a cell that still exists.
        expect(
          c.selection.range,
          const CellRange(top: 0, left: 0, bottom: 0, right: 0),
        );
        c.undo();
        expect(c.rowCount, 3);
        c.dispose();
      });

      test('deleteColumnAt with a count removes the columns', () {
        final c = _grid();
        c.deleteColumnAt(0, count: 2);
        expect(_values(c), [
          ['c'],
          ['f'],
          ['i'],
        ]);
        expect(c.columnWidths.length, 1);
        c.dispose();
      });

      test('clearRow and clearColumn take a count', () {
        final c = _grid();
        c.clearRow(0, count: 2);
        c.clearColumn(2);
        expect(_values(c), [
          ['', '', ''],
          ['', '', ''],
          ['g', 'h', ''],
        ]);
        c.dispose();
      });
    });
  });
}
