import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/spreadsheet_editor/sheet_tab_view.dart';

/// #2692: a sheet tab copies and pastes through the system clipboard, so
/// cells move to and from Google Sheets and Excel.
void main() {
  late String? systemClipboard;

  setUp(() {
    systemClipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              systemClipboard = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return systemClipboard == null ? null : {'text': systemClipboard};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<DataSheetController> pumpTab(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final table = DataTable([
      DataRow([DataCell('a'), DataCell('b')]),
      DataRow([DataCell(''), DataCell('')]),
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
    return controller;
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('Ctrl+C writes the range to the system clipboard ($name)', (
      tester,
    ) async {
      final controller = await pumpTab(tester, size);
      await tester.tap(find.byKey(const ValueKey('r0c0')));
      await tester.pump();
      controller.selection.selectRange(0, 0, 0, 1);

      await ctrl(tester, LogicalKeyboardKey.keyC);

      expect(systemClipboard, 'a\tb');
    });

    testWidgets('the Paste button reads TSV from the system clipboard '
        '($name)', (tester) async {
      final controller = await pumpTab(tester, size);
      systemClipboard = 'x\ty\r\nz\tw\r\n';
      controller.selection.goTo(1, 0);
      await tester.pump();

      final paste = find.byKey(const ValueKey('data_sheet_paste'));
      await tester.ensureVisible(paste);
      await tester.tap(paste);
      await tester.pumpAndSettle();

      expect(controller.cellAt(1, 0).value, 'x');
      expect(controller.cellAt(2, 1).value, 'w');
      expect(controller.rowCount, 3);
    });
  }
}
