import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:data_table/src/data_sheet/cell/heading/heading_cells.dart';
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrow = Size(360, 640);
const _wide = Size(1280, 800);

/// Column B of rows 1–6, under a frozen header row.
const _fruit = ['apple', 'pear', 'apple', '', 'fig', '12'];

Future<DataSheetController> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = DataSheetController.fromTable(
    DataTable([
      DataRow([DataCell('#'), DataCell('Fruit')]),
      for (var i = 0; i < _fruit.length; i++)
        DataRow([DataCell('${i + 1}'), DataCell(_fruit[i])]),
    ]),
    frozenRows: 1,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            DataSheetControlBar(controller: controller),
            Expanded(
              child: DataSheet(controller: controller, table: DataTable([])),
            ),
          ],
        ),
      ),
    ),
  );
  return controller;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
    group('$name viewport', () {
      testWidgets('the header funnel filters rows by value', (tester) async {
        final c = await _pump(tester, size);
        await _tap(tester, 'col_filter_1');
        expect(_key('column_filter_popover'), findsOneWidget);
        expect(find.text('Filter column B'), findsOneWidget);
        expect(find.text('(Blanks)'), findsOneWidget);

        await _tap(tester, 'column_filter_value_apple');
        await _tap(tester, 'column_filter_blanks');
        await _tap(tester, 'column_filter_apply');

        expect(_key('column_filter_popover'), findsNothing);
        expect(c.filterFor(1), const ColumnFilter(hiddenValues: {'apple', ''}));
        // Hidden rows leave the grid; the rest keep their numbers.
        expect(_key('r1c1'), findsNothing);
        expect(_key('row_num_1'), findsNothing);
        expect(_key('r2c1'), findsOneWidget);
        expect(_key('row_num_2'), findsOneWidget);
        expect(_key('r4c1'), findsNothing);
        expect(_key('r5c1'), findsOneWidget);
        expect(c.rowCount, 7);

        final header = tester.widget<ColumnHeaderCell>(_key('col_header_1'));
        expect(header.isFiltered, isTrue);
        expect(header.filterTooltip, contains('4 of 7 rows shown'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('search narrows the list and Select all follows it',
          (tester) async {
        final c = await _pump(tester, size);
        await _tap(tester, 'col_filter_1');
        await tester.enterText(_key('column_filter_search'), 'ap');
        await tester.pumpAndSettle();
        expect(_key('column_filter_value_apple'), findsOneWidget);
        expect(_key('column_filter_value_pear'), findsNothing);

        await _tap(tester, 'column_filter_select_all');
        await _tap(tester, 'column_filter_apply');
        expect(c.filterFor(1), const ColumnFilter(hiddenValues: {'apple'}));
      });

      testWidgets('a condition filters by number', (tester) async {
        final c = await _pump(tester, size);
        await _tap(tester, 'col_filter_0');
        await _tap(tester, 'column_filter_condition');
        await tester.tap(find.text('Greater than').last);
        await tester.pumpAndSettle();
        await tester.enterText(_key('column_filter_condition_value'), '4');
        await _tap(tester, 'column_filter_apply');

        expect(c.visibleRows, [0, 5, 6]);
      });

      testWidgets('Cancel and tapping outside leave the filter alone',
          (tester) async {
        final c = await _pump(tester, size);
        await _tap(tester, 'col_filter_1');
        await _tap(tester, 'column_filter_value_pear');
        await _tap(tester, 'column_filter_cancel');
        expect(c.hasFilters, isFalse);

        await _tap(tester, 'col_filter_1');
        await tester.tapAt(Offset(size.width - 4, size.height - 4));
        await tester.pumpAndSettle();
        expect(_key('column_filter_popover'), findsNothing);
        expect(c.hasFilters, isFalse);
      });

      testWidgets('the popover stays inside the screen', (tester) async {
        await _pump(tester, size);
        await _tap(tester, 'col_filter_1');
        final rect = tester.getRect(_key('column_filter_popover'));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Clear filters in the control bar shows every row again',
          (tester) async {
        final c = await _pump(tester, size);
        expect(
          tester.widget<IconButton>(_key('data_sheet_clear_filters')).onPressed,
          isNull,
        );
        c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'pear'}));
        c.setColumnFilter(0, const ColumnFilter(hiddenValues: {'1'}));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(Badge),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );

        await _tap(tester, 'data_sheet_clear_filters');
        expect(c.hasFilters, isFalse);
        expect(_key('r2c1'), findsOneWidget);
      });

      testWidgets('the control bar opens the selected column\'s filter',
          (tester) async {
        final c = await _pump(tester, size);
        c.selection.setHighlighted(2, 1);
        await tester.pumpAndSettle();
        await _tap(tester, 'data_sheet_filter');
        expect(find.text('Filter column B'), findsOneWidget);
      });

      testWidgets('arrow keys step over hidden rows', (tester) async {
        final c = await _pump(tester, size);
        c.setColumnFilter(1, const ColumnFilter(hiddenValues: {'pear'}));
        await tester.pumpAndSettle();
        await tester.tap(_key('r1c0'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(c.selection.highlightedRow, 3);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(c.selection.highlightedRow, 1);
      });
    });
  }
}
