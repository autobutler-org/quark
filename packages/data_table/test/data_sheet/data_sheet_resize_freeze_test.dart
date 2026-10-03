import 'package:data_table/src/data_sheet/control_bar.dart';
import 'package:data_table/src/data_sheet/data_sheet.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter/gestures.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter_test/flutter_test.dart';

const _narrow = Size(360, 640);
const _wide = Size(1280, 800);

Future<DataSheetController> _pumpSheet(
  WidgetTester tester,
  Size size, {
  int rows = 40,
  int cols = 20,
  bool controlBar = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = DataSheetController.fromTable(
    DataTable(
      List.generate(
        rows,
        (r) => DataRow(List.generate(cols, (c) => DataCell('$r,$c'))),
      ),
    ),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            if (controlBar) DataSheetControlBar(controller: controller),
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

Finder _cell(int r, int c) => _key('r${r}c$c');

/// A drag that moves past the touch slop before it counts, so the whole
/// [offset] reaches the handle.
Future<void> _drag(
  WidgetTester tester,
  Finder finder,
  Offset offset, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: kind,
  );
  const steps = 10;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(offset / steps.toDouble());
    await tester.pump();
  }
  await gesture.up();
  // Let the handle's double-tap timer lapse.
  await tester.pump(kDoubleTapTimeout);
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
    group('resize ($name)', () {
      testWidgets('dragging a column edge resizes it as one undo step', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        final before = tester.getSize(_cell(0, 0)).width;

        await _drag(tester, _key('col_resize_0'), const Offset(60, 0));

        expect(controller.columnWidths[0], closeTo(before + 60, 1));
        expect(tester.getSize(_cell(0, 0)).width, closeTo(before + 60, 1));
        controller.undo();
        await tester.pump();
        expect(controller.columnWidths[0], before);
      });

      testWidgets('dragging a row edge resizes it', (tester) async {
        final controller = await _pumpSheet(tester, size);

        await _drag(tester, _key('row_resize_1'), const Offset(0, 30));

        expect(controller.rowHeights[1], closeTo(70, 1));
        expect(tester.getSize(_cell(1, 0)).height, closeTo(70, 1));
      });

      testWidgets('double-clicking an edge fits the content', (tester) async {
        final controller = await _pumpSheet(tester, size);
        controller.updateCell(
          2,
          1,
          DataCell('a value far too long for a hundred pixels'),
        );
        await tester.pump();

        await _doubleTap(tester, _key('col_resize_1'));

        expect(controller.columnWidths[1], greaterThan(150));
      });

      testWidgets('every handle has a tooltip', (tester) async {
        await _pumpSheet(tester, size);
        expect(
          find.descendant(
            of: _key('col_resize_0'),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Tooltip &&
                  w.message == 'Drag to resize the column, double-click to fit',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _key('row_resize_0'),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Tooltip &&
                  w.message == 'Drag to resize the row, double-click to fit',
            ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('a selected header grows a finger-sized handle', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        expect(tester.getSize(_key('col_resize_1')).width, lessThan(24));

        await tester.tap(_key('col_header_1'));
        await tester.pump();
        expect(tester.getSize(_key('col_resize_1')).width, 24);

        await _drag(
          tester,
          _key('col_resize_1'),
          const Offset(50, 0),
          kind: PointerDeviceKind.touch,
        );
        expect(controller.columnWidths[1], closeTo(150, 1));

        await tester.tap(_key('row_num_3'));
        await tester.pumpAndSettle();
        expect(tester.getSize(_key('row_resize_3')).height, 24);
      });
    });

    group('freeze ($name)', () {
      testWidgets('frozen rows stay put while the body scrolls', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        controller.setFrozenRows(1);
        await tester.pump();
        final frozenTop = tester.getTopLeft(_cell(0, 1)).dy;
        final bodyTop = tester.getTopLeft(_cell(8, 1)).dy;

        await tester.drag(_cell(8, 1), const Offset(0, -200));
        await tester.pumpAndSettle();

        expect(tester.getTopLeft(_cell(0, 1)).dy, frozenTop);
        expect(tester.getTopLeft(_cell(8, 1)).dy, lessThan(bodyTop));
        expect(
          tester.getTopLeft(_key('row_num_9')).dy,
          tester.getTopLeft(_cell(9, 1)).dy,
          reason: 'the row numbers scroll with the body',
        );
        expect(_key('frozen_rows_divider'), findsOneWidget);
        expect(_key('frozen_columns_divider'), findsNothing);
      });

      testWidgets('frozen columns stay put while the body scrolls sideways', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        controller.setFrozenColumns(1);
        await tester.pump();
        final frozenLeft = tester.getTopLeft(_cell(1, 0)).dx;
        final bodyLeft = tester.getTopLeft(_cell(1, 2)).dx;

        await tester.drag(_cell(1, 2), const Offset(-150, 0));
        await tester.pumpAndSettle();

        expect(tester.getTopLeft(_cell(1, 0)).dx, frozenLeft);
        expect(tester.getTopLeft(_cell(1, 2)).dx, lessThan(bodyLeft));
        expect(
          tester.getTopLeft(_key('col_header_2')).dx,
          tester.getTopLeft(_cell(1, 2)).dx,
          reason: 'the column headers scroll with the body',
        );
        expect(_key('frozen_columns_divider'), findsOneWidget);
      });

      testWidgets('scrolling the frozen columns scrolls the body with them', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        controller.setFrozenColumns(1);
        await tester.pump();

        await tester.drag(_cell(5, 0), const Offset(0, -120));
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(_cell(5, 0)).dy,
          tester.getTopLeft(_cell(5, 3)).dy,
        );
      });

      testWidgets('a mouse drag across the freeze line selects by cell', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        controller
          ..setFrozenRows(1)
          ..setFrozenColumns(1);
        await tester.pump();
        await tester.drag(_cell(6, 2), const Offset(-100, -150));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          tester.getCenter(_cell(0, 0)),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(tester.getCenter(_cell(8, 3)));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(controller.selection.highlightedRow, 0);
        expect(controller.selection.highlightedCol, 0);
        expect(controller.selection.extentRow, 8);
        expect(controller.selection.extentCol, 3);
      });

      testWidgets('the freeze menu freezes rows up to the selection', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size, controlBar: true);
        await tester.tap(_cell(1, 1));
        await tester.pump();

        await tester.ensureVisible(_key('data_sheet_freeze'));
        await tester.tap(_key('data_sheet_freeze'));
        await tester.pumpAndSettle();
        await tester.tap(_key('freeze_rows_selection'));
        await tester.pumpAndSettle();
        expect(controller.frozenRows, 2);

        await tester.tap(_key('data_sheet_freeze'));
        await tester.pumpAndSettle();
        await tester.tap(_key('freeze_columns_1'));
        await tester.pumpAndSettle();
        expect(controller.frozenColumns, 1);

        expect(
          find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Freeze rows and columns',
          ),
          findsOneWidget,
        );
      });

      testWidgets('freezing more than fits leaves room to scroll', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        controller
          ..setFrozenRows(40)
          ..setFrozenColumns(20);
        await tester.pump();

        expect(tester.takeException(), isNull);
        final divider = tester.getTopLeft(_key('frozen_rows_divider')).dy;
        final sheetBottom = tester.getBottomLeft(find.byType(DataSheet)).dy;
        expect(divider, lessThan(sheetBottom));
      });
    });
  }
}
