import 'package:data_table/src/data_sheet/cell_range.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

DataSheetController _make(List<List<String>> values) {
  final c = DataSheetController.fromTable(
    DataTable(
      values
          .map((row) => DataRow(row.map((v) => DataCell(v)).toList()))
          .toList(),
    ),
  );
  addTearDown(c.dispose);
  return c;
}

List<List<String>> _values(DataSheetController c) => [
      for (var r = 0; r < c.rowCount; r++)
        [for (var col = 0; col < c.colCount; col++) c.cellAt(r, col).value],
    ];

CellRange _range(int top, int left, int bottom, int right) =>
    CellRange(top: top, left: left, bottom: bottom, right: right);

void main() {
  group('TSV', () {
    test('rangeToTsv joins cells with tabs and rows with newlines', () {
      final c = _make([
        ['a', 'b', 'c'],
        ['d', 'e', 'f'],
      ]);
      expect(c.rangeToTsv(_range(0, 1, 1, 2)), 'b\tc\ne\tf');
    });

    test('rangeToTsv defaults to the selected range', () {
      final c = _make([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      c.selection.selectRange(1, 0, 1, 1);
      expect(c.rangeToTsv(), 'c\td');
    });

    test('rangeToTsv quotes tabs, newlines and quotes the way Sheets does', () {
      final c = _make([
        ['tab\there', 'line\nbreak', 'say "hi"', 'plain'],
      ]);
      expect(
        c.rangeToTsv(_range(0, 0, 0, 3)),
        '"tab\there"\t"line\nbreak"\t"say ""hi"""\tplain',
      );
    });

    test('formulas copy as their text, not their value', () {
      final c = _make([
        ['1', '=A1+1'],
      ]);
      expect(c.displayValueAt(0, 1), '2');
      expect(c.rangeToTsv(_range(0, 0, 0, 1)), '1\t=A1+1');
    });

    test('parseTsv reads quoted fields, CRLF and a trailing newline', () {
      expect(
        DataSheetController.parseTsv(
          '"tab\there"\t"line\r\nbreak"\t"say ""hi"""\r\nx\t\ty\r\n',
        ),
        [
          ['tab\there', 'line\r\nbreak', 'say "hi"'],
          ['x', '', 'y'],
        ],
      );
    });

    test('parseTsv keeps a quote inside an unquoted field literally', () {
      expect(DataSheetController.parseTsv('5" pipe\tok'), [
        ['5" pipe', 'ok'],
      ]);
    });

    test('parseTsv pads ragged rows to the widest', () {
      expect(DataSheetController.parseTsv('a\tb\tc\nd'), [
        ['a', 'b', 'c'],
        ['d', '', ''],
      ]);
    });

    test('copy then paste round-trips awkward values', () {
      final values = [
        ['tab\there', 'line\nbreak'],
        ['say "hi"', '"quoted"'],
        ['', '=SUM(A1:B1)'],
      ];
      final src = _make(values);
      final tsv = src.rangeToTsv(_range(0, 0, 2, 1));
      expect(DataSheetController.parseTsv(tsv), values);

      final dst = _make([
        ['', ''],
        ['', ''],
        ['', ''],
      ]);
      dst.pasteTsv(tsv, _range(0, 0, 0, 0));
      expect(_values(dst), values);
    });
  });

  group('pasteTsv', () {
    test('a block larger than the selection expands from its top-left', () {
      final c = _make([
        ['', '', ''],
        ['', '', ''],
        ['', '', ''],
      ]);
      c.pasteTsv('1\t2\n3\t4', _range(1, 1, 1, 1));
      expect(_values(c), [
        ['', '', ''],
        ['', '1', '2'],
        ['', '3', '4'],
      ]);
      expect(c.selection.range, _range(1, 1, 2, 2));
    });

    test('grows the sheet when the block runs past its edge', () {
      final c = _make([
        ['x', 'y'],
        ['z', 'w'],
      ]);
      c.pasteTsv('1\t2\t3\n4\t5\t6', _range(1, 1, 1, 1));
      expect(c.rowCount, 3);
      expect(c.colCount, 4);
      expect(c.columnWidths.length, 4);
      expect(c.rowHeights.length, 3);
      expect(_values(c), [
        ['x', 'y', '', ''],
        ['z', '1', '2', '3'],
        ['', '4', '5', '6'],
      ]);
    });

    test('a single value fills the whole selected range', () {
      final c = _make([
        ['a', 'b', 'c'],
        ['d', 'e', 'f'],
      ]);
      c.pasteTsv('z', _range(0, 0, 1, 1));
      expect(_values(c), [
        ['z', 'z', 'c'],
        ['z', 'z', 'f'],
      ]);
      expect(c.selection.range, _range(0, 0, 1, 1));
    });

    test('a block tiles a range that is a multiple of its size', () {
      final c = _make([
        ['', '', '', ''],
        ['', '', '', ''],
      ]);
      c.pasteTsv('1\t2', _range(0, 0, 1, 3));
      expect(_values(c), [
        ['1', '2', '1', '2'],
        ['1', '2', '1', '2'],
      ]);
    });

    test('a block that does not divide the range pastes once', () {
      final c = _make([
        ['', '', ''],
        ['', '', ''],
      ]);
      c.pasteTsv('1\t2', _range(0, 0, 1, 2));
      expect(_values(c), [
        ['1', '2', ''],
        ['', '', ''],
      ]);
    });

    test('pasted formulas evaluate', () {
      final c = _make([
        ['2', ''],
      ]);
      c.pasteTsv('=A1*3', _range(0, 1, 0, 1));
      expect(c.displayValueAt(0, 1), '6');
    });

    test('is one undo step, including growth', () {
      final c = _make([
        ['a'],
      ]);
      c.pasteTsv('1\t2\n3\t4', _range(0, 0, 0, 0));
      expect(c.rowCount, 2);
      c.undo();
      expect(_values(c), [
        ['a'],
      ]);
      expect(c.canUndo, false);
      c.redo();
      expect(_values(c), [
        ['1', '2'],
        ['3', '4'],
      ]);
    });

    test('empty text and no selection are no-ops', () {
      final c = _make([
        ['a'],
      ]);
      c.pasteTsv('', _range(0, 0, 0, 0));
      c.pasteTsv('x');
      expect(_values(c), [
        ['a'],
      ]);
      expect(c.canUndo, false);
    });
  });

  group('clearRange', () {
    test('empties every cell in the range as one undo step', () {
      final c = _make([
        ['a', 'b', 'c'],
        ['d', 'e', 'f'],
      ]);
      c.clearRange(_range(0, 1, 1, 2));
      expect(_values(c), [
        ['a', '', ''],
        ['d', '', ''],
      ]);
      c.undo();
      expect(_values(c), [
        ['a', 'b', 'c'],
        ['d', 'e', 'f'],
      ]);
      expect(c.canUndo, false);
    });
  });

  group('fill across a range', () {
    test('fill down copies the top row through the range', () {
      final c = _make([
        ['1', '=A1', 'x'],
        ['', '', 'y'],
        ['', '', 'z'],
        ['k', 'k', 'k'],
      ]);
      c.fillDownRange(_range(0, 0, 2, 1));
      expect(_values(c), [
        ['1', '=A1', 'x'],
        ['1', '=A1', 'y'],
        ['1', '=A1', 'z'],
        ['k', 'k', 'k'],
      ]);
      c.undo();
      expect(c.cellAt(1, 0).value, '');
      expect(c.canUndo, false);
    });

    test('fill right copies the left column through the range', () {
      final c = _make([
        ['a', '', '', 'k'],
        ['b', '', '', 'k'],
      ]);
      c.fillRightRange(_range(0, 0, 1, 2));
      expect(_values(c), [
        ['a', 'a', 'a', 'k'],
        ['b', 'b', 'b', 'k'],
      ]);
    });

    test('a one-row range fills each column to the bottom of the sheet', () {
      final c = _make([
        ['a', 'b', 'c'],
        ['', '', ''],
        ['', '', ''],
      ]);
      c.fillDownRange(_range(0, 0, 0, 1));
      expect(_values(c), [
        ['a', 'b', 'c'],
        ['a', 'b', ''],
        ['a', 'b', ''],
      ]);
    });
  });

  group('deleting a range inside the frozen band', () {
    test('rows shrink the band by how many frozen rows went', () {
      final c = DataSheetController.fromTable(
        DataTable(List.generate(6, (r) => DataRow([DataCell('$r')]))),
        frozenRows: 3,
      );
      addTearDown(c.dispose);
      c.deleteRowAt(2, count: 3);
      expect(c.frozenRows, 2);
      c.deleteRowAt(0, count: 1);
      expect(c.frozenRows, 1);
    });

    test('columns shrink the band by how many frozen columns went', () {
      final c = DataSheetController.fromTable(
        DataTable([
          DataRow(List.generate(6, (i) => DataCell('$i'))),
        ]),
        frozenColumns: 2,
      );
      addTearDown(c.dispose);
      c.deleteColumnAt(0, count: 4);
      expect(c.frozenColumns, 0);
      expect(c.colCount, 2);
    });
  });
}
