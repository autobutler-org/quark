import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/spreadsheet_editor/sheet_tab_view.dart';

// The control bar scrolls sideways on a phone, and a mouse user with no wheel
// gets a chevron to reach the far end (#2770).
void main() {
  testWidgets('a mouse gets a chevron that scrolls the control bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final table = DataTable([
      DataRow([DataCell('a')]),
    ]);
    final controller = DataSheetController.fromTable(table);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SheetTabView(controller: controller, table: table),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 300));
    addTearDown(mouse.removePointer);
    await tester.pump();

    expect(find.byKey(const ValueKey('toolbar_scroll_left')), findsNothing);
    final before = tester.getTopLeft(find.byType(DataSheetControlBar)).dx;
    await tester.tap(find.byKey(const ValueKey('toolbar_scroll_right')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(DataSheetControlBar)).dx,
      lessThan(before),
    );
    expect(find.byKey(const ValueKey('toolbar_scroll_left')), findsOneWidget);
  });
}
