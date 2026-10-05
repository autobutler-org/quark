import 'package:data_table/src/data_sheet/cell_range.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<String>> _values(DataSheetController c) => [
      for (var r = 0; r < c.rowCount; r++)
        [for (var col = 0; col < c.colCount; col++) c.cellAt(r, col).value],
    ];

/// A 3x3 sheet of `a`..`i`, row by row.
DataSheetController _grid() => _makeController([
      ['a', 'b', 'c'],
      ['d', 'e', 'f'],
      ['g', 'h', 'i'],
    ]);

DataTable _makeTable(List<List<String>> values) {
  return DataTable(
    values.map((row) => DataRow(row.map((v) => DataCell(v)).toList())).toList(),
  );
}

DataSheetController _makeController(List<List<String>> values) {
  return DataSheetController.fromTable(_makeTable(values));
}

void main() {
  group('DataSheetController', () {
    group('fromTable', () {
      test('rowCount and colCount match the table', () {
        final c = _makeController([
          ['a', 'b', 'c'],
          ['d', 'e', 'f'],
        ]);
        expect(c.rowCount, 2);
        expect(c.colCount, 3);
        c.dispose();
      });

      test('cellAt returns the correct value', () {
        final c = _makeController([
          ['x', 'y'],
        ]);
        expect(c.cellAt(0, 0).value, 'x');
        expect(c.cellAt(0, 1).value, 'y');
        c.dispose();
      });

      test('columnWidths defaults to kDefaultColumnWidth for each column', () {
        final c = _makeController([
          ['a', 'b', 'c'],
        ]);
        expect(c.columnWidths, [100.0, 100.0, 100.0]);
        c.dispose();
      });

      test('columnWidths is growable (no fixed-length crash)', () {
        final c = _makeController([
          ['a', 'b'],
        ]);
        expect(() => c.columnWidths.add(100.0), returnsNormally);
        c.dispose();
      });

      test('accepts custom columnWidths', () {
        final table = _makeTable([
          ['a', 'b'],
        ]);
        final c =
            DataSheetController.fromTable(table, columnWidths: [120.0, 80.0]);
        expect(c.columnWidths, [120.0, 80.0]);
        c.dispose();
      });
    });

    group('updateCell', () {
      test('updates cell value', () {
        final c = _makeController([
          ['old', 'b'],
        ]);
        c.updateCell(0, 0, DataCell('new'));
        expect(c.cellAt(0, 0).value, 'new');
        c.dispose();
      });

      test('notifies listeners', () {
        final c = _makeController([
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
        final c = _makeController([
          ['hello', 'world'],
        ]);
        c.clearCell(0, 0);
        expect(c.cellAt(0, 0).value, '');
        expect(c.cellAt(0, 1).value, 'world');
        c.dispose();
      });

      test('does nothing for out-of-bounds indices', () {
        final c = _makeController([
          ['a'],
        ]);
        expect(() => c.clearCell(5, 5), returnsNormally);
        c.dispose();
      });
    });

    group('clearRow', () {
      test('clears all cells in the row', () {
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
          ['a'],
        ]);
        c.insertRowAt(99);
        expect(c.rowCount, 2);
        c.dispose();
      });
    });

    group('deleteRowAt', () {
      test('removes the row at index', () {
        final c = _makeController([
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
        final c = _makeController([
          ['a'],
        ]);
        expect(() => c.deleteRowAt(5), returnsNormally);
        expect(c.rowCount, 1);
        c.dispose();
      });
    });

    group('duplicateRow', () {
      test('inserts copy immediately after source', () {
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
          ['a'],
        ]);
        c.addColumn();
        expect(c.columnWidths.length, 2);
        c.dispose();
      });
    });

    group('deleteColumnAt', () {
      test('removes the column at index', () {
        final c = _makeController([
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
        final c = _makeController([
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
      test('rowHeights defaults to kDefaultRowHeight for each row', () {
        final c = _makeController([
          ['a'],
          ['b'],
          ['c'],
        ]);
        expect(c.rowHeights, [40.0, 40.0, 40.0]);
        c.dispose();
      });

      test('addRow appends a new rowHeight', () {
        final c = _makeController([
          ['a']
        ]);
        c.addRow();
        expect(c.rowHeights.length, 2);
        c.dispose();
      });

      test('insertRowAt inserts a rowHeight at the correct index', () {
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
          ['a', 'b']
        ]);
        c.setColumnWidth(0, 150.0);
        expect(c.columnWidths[0], 150.0);
        c.dispose();
      });

      test('clamps to kMinColumnWidth', () {
        final c = _makeController([
          ['a']
        ]);
        c.setColumnWidth(0, 0.0);
        expect(c.columnWidths[0], 24.0);
        c.dispose();
      });

      test('does nothing for out-of-range index', () {
        final c = _makeController([
          ['a']
        ]);
        expect(() => c.setColumnWidth(5, 100.0), returnsNormally);
        c.dispose();
      });
    });

    group('setRowHeight', () {
      test('updates the height at the given index', () {
        final c = _makeController([
          ['a'],
          ['b']
        ]);
        c.setRowHeight(1, 60.0);
        expect(c.rowHeights[1], 60.0);
        c.dispose();
      });

      test('clamps to kMinRowHeight', () {
        final c = _makeController([
          ['a']
        ]);
        c.setRowHeight(0, 0.0);
        expect(c.rowHeights[0], 24.0);
        c.dispose();
      });
    });

    group('autoSizeColumn', () {
      test('sets width >= kMinColumnWidth for non-empty column', () {
        final c = _makeController([
          ['Hello World'],
          ['Short'],
        ]);
        c.autoSizeColumn(0);
        expect(c.columnWidths[0], greaterThanOrEqualTo(24.0));
        c.dispose();
      });

      test('does nothing for out-of-range column', () {
        final c = _makeController([
          ['a']
        ]);
        expect(() => c.autoSizeColumn(5), returnsNormally);
        c.dispose();
      });
    });

    group('autoSizeRow', () {
      test('sets height >= kMinRowHeight', () {
        final c = _makeController([
          ['Hello World']
        ]);
        c.autoSizeRow(0);
        expect(c.rowHeights[0], greaterThanOrEqualTo(24.0));
        c.dispose();
      });

      test('does nothing for out-of-range row', () {
        final c = _makeController([
          ['a']
        ]);
        expect(() => c.autoSizeRow(5), returnsNormally);
        c.dispose();
      });
    });

    group('sortByColumn', () {
      test('sorts lexicographically ascending', () {
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
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
        final c = _makeController([
          ['Hello'],
        ]);
        expect(c.findCells('hello').length, 1);
        c.dispose();
      });

      test('is case-sensitive when requested', () {
        final c = _makeController([
          ['Hello'],
        ]);
        expect(c.findCells('hello', caseSensitive: true).length, 0);
        c.dispose();
      });

      test('returns empty list when no match', () {
        final c = _makeController([
          ['abc'],
        ]);
        expect(c.findCells('xyz'), isEmpty);
        c.dispose();
      });
    });

    group('replaceCells', () {
      test('replaces all occurrences and returns count', () {
        final c = _makeController([
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
        final c = _makeController([
          ['abc'],
        ]);
        final count = c.replaceCells('', 'x');
        expect(count, 0);
        expect(c.cellAt(0, 0).value, 'abc');
        c.dispose();
      });
    });

    group('exportCsv / loadFromCsv', () {
      test('exportCsv produces correct output', () {
        final c = _makeController([
          ['a', 'b'],
          ['c', 'd'],
        ]);
        expect(c.exportCsv(), 'a,b\nc,d');
        c.dispose();
      });

      test('exportCsv quotes cells containing commas', () {
        final c = _makeController([
          ['hello, world'],
        ]);
        expect(c.exportCsv(), '"hello, world"');
        c.dispose();
      });

      test('exportCsv quotes cells containing double-quotes', () {
        final c = _makeController([
          ['say "hi"'],
        ]);
        expect(c.exportCsv(), '"say ""hi"""');
        c.dispose();
      });

      test('loadFromCsv round-trips with exportCsv', () {
        final c = _makeController([
          ['x', 'y'],
          ['1', '2'],
        ]);
        final csv = c.exportCsv();
        c.loadFromCsv(csv);
        expect(c.rowCount, 2);
        expect(c.cellAt(0, 0).value, 'x');
        expect(c.cellAt(1, 1).value, '2');
        c.dispose();
      });
    });

    group('undo / redo', () {
      test('canUndo is false initially', () {
        final c = _makeController([
          ['a'],
        ]);
        expect(c.canUndo, false);
        c.dispose();
      });

      test('canUndo becomes true after a mutating operation', () {
        final c = _makeController([
          ['a'],
        ]);
        c.clearCell(0, 0);
        expect(c.canUndo, true);
        c.dispose();
      });

      test('undo reverses last change', () {
        final c = _makeController([
          ['original'],
        ]);
        c.clearCell(0, 0);
        c.undo();
        expect(c.cellAt(0, 0).value, 'original');
        c.dispose();
      });

      test('redo reapplies undone change', () {
        final c = _makeController([
          ['original'],
        ]);
        c.clearCell(0, 0);
        c.undo();
        c.redo();
        expect(c.cellAt(0, 0).value, '');
        c.dispose();
      });

      test('redo stack is cleared after a new mutation', () {
        final c = _makeController([
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

      test('clearRange empties every cell in one undo step', () {
        final c = _grid();
        c.clearRange(topLeft);
        expect(_values(c), [
          ['', '', 'c'],
          ['', '', 'f'],
          ['g', 'h', 'i'],
        ]);
        c.undo();
        expect(c.valuesIn(topLeft), [
          ['a', 'b'],
          ['d', 'e'],
        ]);
        expect(c.canUndo, false);
        c.dispose();
      });

      test('pasteValues lands a block at the top-left, growing the sheet', () {
        final c = _grid();
        c.pasteValues(
          const CellRange(top: 1, left: 1, bottom: 1, right: 1),
          [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ],
        );
        expect(_values(c), [
          ['a', 'b', 'c', ''],
          ['d', '1', '2', '3'],
          ['g', '4', '5', '6'],
          ['', '7', '8', '9'],
        ]);
        c.dispose();
      });

      test('pasteValues fills the range with a single value', () {
        final c = _grid();
        c.pasteValues(topLeft, [
          ['x'],
        ]);
        expect(c.valuesIn(topLeft), [
          ['x', 'x'],
          ['x', 'x'],
        ]);
        expect(c.cellAt(2, 2).value, 'i');
        c.dispose();
      });

      test('fillDownRange copies the top row through the range', () {
        final c = _grid();
        c.fillDownRange(topLeft);
        expect(_values(c), [
          ['a', 'b', 'c'],
          ['a', 'b', 'f'],
          ['g', 'h', 'i'],
        ]);
        c.dispose();
      });

      test('fillDownRange on one row fills to the bottom', () {
        final c = _grid();
        c.fillDownRange(const CellRange(top: 0, left: 1, bottom: 0, right: 2));
        expect(_values(c), [
          ['a', 'b', 'c'],
          ['d', 'b', 'c'],
          ['g', 'b', 'c'],
        ]);
        c.dispose();
      });

      test('fillRightRange copies the left column through the range', () {
        final c = _grid();
        c.fillRightRange(topLeft);
        expect(_values(c), [
          ['a', 'a', 'c'],
          ['d', 'd', 'f'],
          ['g', 'h', 'i'],
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
        expect(c.selection.range,
            const CellRange(top: 0, left: 0, bottom: 0, right: 0));
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
