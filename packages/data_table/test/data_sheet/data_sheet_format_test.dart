import 'dart:convert';

import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
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

/// A [rows] by [cols] sheet whose cells hold `r,c`.
DataSheetController _grid(int rows, int cols) => _make([
      for (var r = 0; r < rows; r++) [for (var c = 0; c < cols; c++) '$r,$c'],
    ]);

CellRange _range(int top, int left, int bottom, int right) =>
    CellRange(top: top, left: left, bottom: bottom, right: right);

CellRange _cell(int r, int c) => _range(r, c, r, c);

const _bold = CellFormat(bold: true);

/// The formatted cells, keyed `"r,c"`, with the bold ones marked.
Set<String> _boldCells(DataSheetController c) => {
      for (final MapEntry(key: (r, col), value: f) in c.formats.entries)
        if (f.bold) '$r,$col',
    };

void main() {
  group('applyFormat', () {
    test('formats every cell in the range as one undo step', () {
      final c = _grid(3, 3);
      c.applyFormat(_range(0, 0, 1, 1), (f) => f.withBold(true));
      expect(_boldCells(c), {'0,0', '0,1', '1,0', '1,1'});
      expect(c.formatAt(2, 2), CellFormat.plain);
      c.undo();
      expect(c.formats, isEmpty);
      c.redo();
      expect(_boldCells(c), hasLength(4));
    });

    test('keeps each cell\'s other fields', () {
      final c = _grid(1, 2);
      c.applyFormat(_cell(0, 0), (f) => f.withItalic(true));
      c.applyFormat(_range(0, 0, 0, 1), (f) => f.withBold(true));
      expect(c.formatAt(0, 0), const CellFormat(bold: true, italic: true));
      expect(c.formatAt(0, 1), _bold);
    });

    test('records no undo step when nothing changes', () {
      final c = _grid(2, 2);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(false));
      expect(c.canUndo, isFalse);
    });

    test('a format that becomes plain is dropped, keeping storage sparse', () {
      final c = _grid(2, 2);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(true));
      c.applyFormat(_cell(0, 0), (f) => f.withBold(false));
      expect(c.formats, isEmpty);
    });

    test('skips rows a filter hides', () {
      final c = _make([
        ['keep'],
        ['drop'],
        ['keep'],
      ]);
      c.setColumnFilter(0, const ColumnFilter(hiddenValues: {'drop'}));
      c.applyFormat(_range(0, 0, 2, 0), (f) => f.withBold(true));
      expect(_boldCells(c), {'0,0', '2,0'});
    });

    test('clearFormats removes formats and keeps values', () {
      final c = _grid(2, 2);
      c.applyFormat(_range(0, 0, 1, 1), (f) => f.withBold(true));
      c.clearFormats(_range(0, 0, 0, 1));
      expect(_boldCells(c), {'1,0', '1,1'});
      expect(c.cellAt(0, 0).value, '0,0');
    });
  });

  group('number formats', () {
    test('change the display, never the value or the formulas reading it', () {
      final c = _make([
        ['0.25', '=A1*2'],
      ]);
      c.applyFormat(
        _cell(0, 0),
        (f) => f.withNumberFormat(CellNumberFormat.percent),
      );
      expect(c.cellAt(0, 0).value, '0.25');
      expect(c.displayValueAt(0, 0), '0.25');
      expect(c.formattedValueAt(0, 0), '25.00%');
      expect(c.displayValueAt(0, 1), '0.5');
      expect(c.formattedValueAt(0, 1), '0.5');
    });

    test('apply to a formula\'s result', () {
      final c = _make([
        ['1000', '=A1*2'],
      ]);
      c.applyFormat(
        _cell(0, 1),
        (f) => f.withNumberFormat(CellNumberFormat.currency),
      );
      expect(c.formattedValueAt(0, 1), r'$2,000.00');
      expect(c.cellAt(0, 1).value, '=A1*2');
    });

    test('sort and filters read the raw value', () {
      final c = _make([
        ['10'],
        ['9'],
      ]);
      c.applyFormat(
        _range(0, 0, 1, 0),
        (f) => f.withNumberFormat(CellNumberFormat.currency),
      );
      c.sortByColumn(0);
      expect(c.cellAt(0, 0).value, '9');
      c.setColumnFilter(
        0,
        const ColumnFilter(
          condition: FilterCondition(FilterConditionKind.greaterThan, '9.5'),
        ),
      );
      expect(c.visibleRows, [1]);
    });
  });

  group('formats follow their cells', () {
    test('inserting a row moves the formats below it down', () {
      final c = _grid(3, 1);
      c.applyFormat(_cell(1, 0), (f) => f.withBold(true));
      c.insertRowAt(1);
      expect(_boldCells(c), {'2,0'});
      c.undo();
      expect(_boldCells(c), {'1,0'});
    });

    test('deleting rows drops their formats and moves the rest up', () {
      final c = _grid(4, 1);
      c.applyFormat(_cell(1, 0), (f) => f.withBold(true));
      c.applyFormat(_cell(3, 0), (f) => f.withBold(true));
      c.deleteRowAt(0, count: 2);
      expect(_boldCells(c), {'1,0'});
    });

    test('inserting and deleting columns move formats sideways', () {
      final c = _grid(1, 4);
      c.applyFormat(_cell(0, 2), (f) => f.withBold(true));
      c.insertColumnAt(0);
      expect(_boldCells(c), {'0,3'});
      c.deleteColumnAt(0, count: 2);
      expect(_boldCells(c), {'0,1'});
      c.deleteColumnAt(1);
      expect(c.formats, isEmpty);
    });

    test('duplicating a row or column copies its formats', () {
      final c = _grid(2, 2);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(true));
      c.duplicateRow(0);
      expect(_boldCells(c), {'0,0', '1,0'});
      c.duplicateColumn(0);
      expect(_boldCells(c), {'0,0', '0,1', '1,0', '1,1'});
    });

    test('sorting carries each row\'s formats with it', () {
      final c = _make([
        ['b'],
        ['c'],
        ['a'],
      ]);
      c.applyFormat(_cell(1, 0), (f) => f.withBold(true));
      c.sortByColumn(0);
      expect(c.cellAt(2, 0).value, 'c');
      expect(_boldCells(c), {'2,0'});
    });

    test('removing duplicate rows moves formats with the rows kept', () {
      final c = _make([
        ['a'],
        ['a'],
        ['b'],
      ]);
      c.applyFormat(_cell(2, 0), (f) => f.withBold(true));
      c.removeDuplicateRows();
      expect(_boldCells(c), {'1,0'});
    });

    test('filters leave formats on their rows', () {
      final c = _make([
        ['keep'],
        ['drop'],
      ]);
      c.applyFormat(_cell(1, 0), (f) => f.withBold(true));
      c.setColumnFilter(0, const ColumnFilter(hiddenValues: {'drop'}));
      c.clearFilters();
      expect(_boldCells(c), {'1,0'});
    });

    test('importing CSV clears every format', () {
      final c = _grid(2, 2);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(true));
      c.loadFromCsv('x,y');
      expect(c.formats, isEmpty);
    });
  });

  group('copy and paste', () {
    test('pasting this sheet\'s copy brings the formats along', () {
      final c = _grid(4, 2);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(true));
      c.applyFormat(_cell(0, 1), (f) => f.withFillColor(0xFF10B981));
      final tsv = c.copyRange(_range(0, 0, 0, 1));
      c.pasteTsv(tsv, _range(2, 0, 3, 1));
      expect(c.cellAt(3, 1).value, '0,1');
      expect(c.formatAt(2, 0), _bold);
      expect(c.formatAt(3, 0), _bold);
      expect(c.formatAt(3, 1).fillColor, 0xFF10B981);
      c.undo();
      expect(_boldCells(c), {'0,0'});
    });

    test('a plain source cell clears the target\'s format', () {
      final c = _grid(2, 1);
      c.applyFormat(_cell(1, 0), (f) => f.withBold(true));
      c.pasteTsv(c.copyRange(_cell(0, 0)), _cell(1, 0));
      expect(c.formats, isEmpty);
    });

    test('text from elsewhere pastes values only', () {
      final c = _grid(2, 1);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(true));
      c.copyRange(_cell(0, 0));
      c.pasteTsv('other', _cell(1, 0));
      expect(c.cellAt(1, 0).value, 'other');
      expect(_boldCells(c), {'0,0'});
    });

    test('cut moves values and formats', () async {
      final c = _grid(2, 1);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(true));
      String? board;
      final clipboard = DataSheetClipboard(
        read: () async => board,
        write: (text) async => board = text,
      );
      await clipboard.cutSelection(c, _cell(0, 0));
      expect(c.cellAt(0, 0).value, '');
      expect(c.formats, isEmpty);
      await clipboard.pasteIntoSelection(c, _cell(1, 0));
      expect(c.cellAt(1, 0).value, '0,0');
      expect(_boldCells(c), {'1,0'});
    });

    test('Delete keeps formats', () {
      final c = _grid(1, 1);
      c.applyFormat(_cell(0, 0), (f) => f.withBold(true));
      c.clearRange(_cell(0, 0));
      expect(c.cellAt(0, 0).value, '');
      expect(_boldCells(c), {'0,0'});
    });
  });

  group('persistence', () {
    test('formats round-trip through the saved layout', () {
      final c = _grid(2, 2);
      c.applyFormat(
        _cell(1, 1),
        (f) => f
            .withBold(true)
            .withAlign(CellAlign.right)
            .withNumberFormat(CellNumberFormat.currency)
            .withDecimals(0),
      );
      final saved = jsonDecode(jsonEncode(c.layoutToJson())) as Map;
      expect(saved['formats'], [
        {
          'row': 1,
          'col': 1,
          'bold': true,
          'align': 'right',
          'numberFormat': 'currency',
          'decimals': 0,
        },
      ]);
      final loaded = DataSheetController.fromLayoutJson(
        DataTable([
          DataRow([DataCell('a'), DataCell('b')]),
          DataRow([DataCell('c'), DataCell('5')]),
        ]),
        saved.cast<String, dynamic>(),
      );
      addTearDown(loaded.dispose);
      expect(loaded.formatAt(1, 1), c.formatAt(1, 1));
      expect(loaded.formattedValueAt(1, 1), r'$5');
    });

    test('a sheet saved before formats existed loads unformatted', () {
      final c = DataSheetController.fromLayoutJson(
        DataTable([
          DataRow([DataCell('1')]),
        ]),
        {
          'columnWidths': [100],
          'frozenRows': 0,
        },
      );
      addTearDown(c.dispose);
      expect(c.formats, isEmpty);
      expect(c.formattedValueAt(0, 0), '1');
    });

    test('unreadable and out-of-range entries are skipped', () {
      final c = DataSheetController.fromLayoutJson(
        DataTable([
          DataRow([DataCell('1')]),
        ]),
        {
          'formats': [
            'bold',
            {'row': 'x', 'col': 0, 'bold': true},
            {'row': 5, 'col': 0, 'bold': true},
            {'row': 0, 'col': 0},
            {'row': 0, 'col': 0, 'italic': true, 'align': 'sideways'},
          ],
        },
      );
      addTearDown(c.dispose);
      expect(c.formats, {(0, 0): const CellFormat(italic: true)});
    });

    test('a non-list formats value loads unformatted', () {
      final c = DataSheetController.fromLayoutJson(
        DataTable([
          DataRow([DataCell('1')]),
        ]),
        {'formats': 'oops'},
      );
      addTearDown(c.dispose);
      expect(c.formats, isEmpty);
    });
  });
}
