import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sheet with a header row and one row per entry of [values], each holding
/// its row number in column A and the value in column B.
DataSheetController _sheet(List<String> values, {int frozenRows = 1}) {
  final c = DataSheetController.fromTable(
    DataTable([
      DataRow([DataCell('#'), DataCell('Item')]),
      for (var i = 0; i < values.length; i++)
        DataRow([DataCell('${i + 1}'), DataCell(values[i])]),
    ]),
    frozenRows: frozenRows,
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ColumnFilter', () {
    test('hides unchecked values and treats whitespace as blank', () {
      const f = ColumnFilter(hiddenValues: {'b', ''});
      expect(f.accepts('a'), isTrue);
      expect(f.accepts('b'), isFalse);
      expect(f.accepts(''), isFalse);
      expect(f.accepts('   '), isFalse);
      expect(f.isActive, isTrue);
      expect(const ColumnFilter().isActive, isFalse);
    });

    test('text conditions ignore case', () {
      bool m(FilterConditionKind k, String operand, String v) =>
          ColumnFilter(condition: FilterCondition(k, operand)).accepts(v);
      expect(m(FilterConditionKind.contains, 'APP', 'apple'), isTrue);
      expect(m(FilterConditionKind.contains, 'x', 'apple'), isFalse);
      expect(m(FilterConditionKind.doesNotContain, 'x', 'apple'), isTrue);
      expect(m(FilterConditionKind.equals, 'Apple', 'apple'), isTrue);
    });

    test('number conditions compare numerically and reject text', () {
      bool m(FilterConditionKind k, String operand, String v) =>
          ColumnFilter(condition: FilterCondition(k, operand)).accepts(v);
      expect(m(FilterConditionKind.greaterThan, '9', '10'), isTrue);
      expect(m(FilterConditionKind.greaterThan, '10', '9'), isFalse);
      expect(m(FilterConditionKind.lessThan, '10', '9.5'), isTrue);
      expect(m(FilterConditionKind.lessThan, '10', 'abc'), isFalse);
      expect(m(FilterConditionKind.equals, '2', '2.0'), isTrue);
    });

    test('round-trips through JSON and skips what it cannot read', () {
      const f = ColumnFilter(
        hiddenValues: {'a', ''},
        condition: FilterCondition(FilterConditionKind.greaterThan, '3'),
      );
      expect(ColumnFilter.fromJson(f.toJson()), f);
      expect(ColumnFilter.fromJson('nope'), isNull);
      expect(
        ColumnFilter.fromJson({
          'hidden': [1, 'x'],
          'condition': {'kind': 'unknown', 'value': 'y'},
        }),
        const ColumnFilter(hiddenValues: {'x'}),
      );
    });
  });

  group('filtering rows', () {
    test('hides rows without deleting them and keeps their indexes', () {
      final c = _sheet(['apple', 'pear', 'apple', '']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'pear', ''}));

      expect(c.rowCount, 5);
      expect(c.visibleRows, [0, 1, 3]);
      expect(c.isRowHidden(2), isTrue);
      expect(c.isRowHidden(4), isTrue);
      expect(c.cellAt(2, 1).value, 'pear');
      expect(c.hasFilters, isTrue);
    });

    test('never hides frozen header rows', () {
      final c = _sheet(['a', 'b']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'Item', 'a'}));
      expect(c.visibleRows, [0, 2]);
    });

    test('filters on every filtered column at once', () {
      final c = _sheet(['a', 'b', 'a']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
      c.setColumnFilter(
        0,
        const ColumnFilter(
          condition: FilterCondition(FilterConditionKind.greaterThan, '1'),
        ),
      );
      expect(c.visibleRows, [0, 3]);
    });

    test('lists the column values below the frozen rows, blank included', () {
      final c = _sheet(['pear', 'apple', '', 'pear', '10', '9']);
      expect(c.filterValuesFor(1), ['9', '10', 'apple', 'pear', '']);
    });

    test(
      'an inactive filter clears the column, and Clear filters clears all',
      () {
        final c = _sheet(['a', 'b']);
        c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
        c.setColumnFilter(1, const ColumnFilter());
        expect(c.hasFilters, isFalse);
        expect(c.visibleRows, [0, 1, 2]);

        c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
        c.setColumnFilter(0, const ColumnFilter(hiddenValues: {'1'}));
        c.clearFilters();
        expect(c.filters, isEmpty);
        expect(c.visibleRows, [0, 1, 2]);
      },
    );

    test('setting and clearing a filter are undoable', () {
      final c = _sheet(['a', 'b']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
      c.undo();
      expect(c.hasFilters, isFalse);
      expect(c.visibleRows, [0, 1, 2]);
      c.redo();
      expect(c.visibleRows, [0, 1]);
    });

    test('an edited row stays visible until the filters change', () {
      final c = _sheet(['a', 'b']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
      c.updateCell(1, 1, DataCell('b'));
      expect(c.visibleRows, [0, 1]);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b', 'x'}));
      expect(c.visibleRows, [0]);
    });

    test('clears a selection that lands on a hidden row', () {
      final c = _sheet(['a', 'b']);
      c.selection.setHighlighted(2, 1);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
      expect(c.selection.hasHighlight, isFalse);
    });

    test('steps over hidden rows', () {
      final c = _sheet(['a', 'b', 'b', 'a']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
      expect(c.nextVisibleRow(1, 1), 4);
      expect(c.nextVisibleRow(4, -1), 1);
      expect(c.nextVisibleRow(4, 1), 4);
    });
  });

  group('range operations skip hidden rows', () {
    late DataSheetController c;
    setUp(() {
      c = _sheet(['a', 'b', 'a', 'b', 'a']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
    });

    CellRange all() => CellRange(top: 1, left: 0, bottom: 5, right: 1);

    test('copy takes only visible rows', () {
      expect(c.rangeToTsv(all()), '1\ta\n3\ta\n5\ta');
    });

    test('clear leaves hidden rows alone', () {
      c.clearRange(all());
      expect(c.cellAt(2, 1).value, 'b');
      expect(c.cellAt(1, 1).value, '');
      expect(c.cellAt(5, 0).value, '');
    });

    test('paste writes consecutive visible rows', () {
      c.pasteValues(CellRange(top: 1, left: 0, bottom: 1, right: 0), [
        ['x'],
        ['y'],
      ]);
      expect(c.cellAt(1, 0).value, 'x');
      expect(c.cellAt(2, 0).value, '2');
      expect(c.cellAt(3, 0).value, 'y');
      expect(
        c.selection.range,
        CellRange(top: 1, left: 0, bottom: 3, right: 0),
      );
    });

    test('a single pasted value fills every visible row of the target', () {
      c.pasteValues(all(), [
        ['z'],
      ]);
      expect(
        [for (var r = 1; r <= 5; r++) c.cellAt(r, 0).value],
        ['z', '2', 'z', '4', 'z'],
      );
    });

    test('paste past the last visible row grows the sheet', () {
      c.pasteValues(CellRange(top: 5, left: 0, bottom: 5, right: 0), [
        ['p'],
        ['q'],
      ]);
      expect(c.rowCount, 7);
      expect(c.cellAt(6, 0).value, 'q');
      expect(c.isRowHidden(6), isFalse);
    });

    test(
      'fill down copies the first visible row to the other visible ones',
      () {
        c.updateCell(1, 0, DataCell('top'));
        c.fillDownRange(all());
        expect(
          [for (var r = 1; r <= 5; r++) c.cellAt(r, 0).value],
          ['top', '2', 'top', '4', 'top'],
        );
      },
    );

    test('delete row removes only the visible rows in the range', () {
      c.deleteRowAt(1, count: 5);
      expect(c.rowCount, 3);
      expect(c.cellAt(1, 1).value, 'b');
      expect(c.cellAt(2, 1).value, 'b');
      expect(c.visibleRows, [0]);
    });
  });

  group('structure keeps filters on their columns and rows', () {
    test('inserted rows are visible and hidden rows move with the insert', () {
      final c = _sheet(['a', 'b']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b', ''}));
      c.insertRowAt(1);
      expect(c.visibleRows, [0, 1, 2]);
      expect(c.isRowHidden(3), isTrue);
    });

    test('a column insert or delete moves the filter with its column', () {
      final c = _sheet(['a', 'b']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
      c.insertColumnAt(0);
      expect(c.filterFor(2), isNotNull);
      expect(c.filterFor(1), isNull);
      c.deleteColumnAt(0);
      expect(c.filterFor(1), isNotNull);
      c.deleteColumnAt(1);
      expect(c.hasFilters, isFalse);
      expect(c.visibleRows, [0, 1, 2]);
    });

    test('sort carries hidden rows with their data', () {
      final c = _sheet(['b', 'a', 'c']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'a'}));
      c.sortByColumn(0, ascending: false);
      // Rows sorted by column A descending: header '#' is text, so it sorts
      // with the rest; find the hidden row by its value instead.
      final hidden = [
        for (var r = 0; r < c.rowCount; r++)
          if (c.isRowHidden(r)) c.cellAt(r, 1).value,
      ];
      expect(hidden, ['a']);
    });

    test('importing CSV clears the filters', () {
      final c = _sheet(['a', 'b']);
      c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'b'}));
      c.loadFromCsv('x,y\nb,b');
      expect(c.hasFilters, isFalse);
      expect(c.visibleRows, [0, 1]);
    });
  });

  group('persistence', () {
    DataTable table() => DataTable([
          DataRow([DataCell('h')]),
          DataRow([DataCell('a')]),
          DataRow([DataCell('b')]),
        ]);

    test('filters round-trip through the layout JSON', () {
      final c = DataSheetController.fromTable(table(), frozenRows: 1);
      addTearDown(c.dispose);
      c.setColumnFilter(0, const ColumnFilter(hiddenValues: {'b'}));
      final json = c.layoutToJson();

      final copy = DataSheetController.fromLayoutJson(table(), json);
      addTearDown(copy.dispose);
      expect(copy.filterFor(0), const ColumnFilter(hiddenValues: {'b'}));
      expect(copy.visibleRows, [0, 1]);
    });

    test('a sheet saved before filters loads with none', () {
      final c = DataSheetController.fromLayoutJson(table(), {
        'columnWidths': [120],
        'frozenRows': 1,
      });
      addTearDown(c.dispose);
      expect(c.hasFilters, isFalse);
      expect(c.visibleRows, [0, 1, 2]);
    });

    test('broken or out-of-range filter entries are skipped', () {
      final c = DataSheetController.fromLayoutJson(table(), {
        'filters': [
          'junk',
          {
            'column': 7,
            'hidden': ['a'],
          },
          {'column': 'x'},
          {
            'column': 0,
            'hidden': ['a'],
          },
        ],
      });
      addTearDown(c.dispose);
      expect(c.filters.keys, [0]);
      expect(c.visibleRows, [0, 2]);
    });
  });
}
