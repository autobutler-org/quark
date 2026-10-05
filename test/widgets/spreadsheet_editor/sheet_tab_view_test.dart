import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/spreadsheet_editor/sheet_format_palette.dart';
import 'package:quark/widgets/spreadsheet_editor/sheet_tab_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2692: a sheet tab copies and pastes through the system clipboard, so
/// cells move to and from Google Sheets and Excel. #2693: it carries the
/// formatting toolbar.
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

    // #2693: formatting survives a copy and paste through the system
    // clipboard within the sheet.
    testWidgets('Ctrl+C then Ctrl+V carries cell formats ($name)', (
      tester,
    ) async {
      final controller = await pumpTab(tester, size);
      await tester.tap(find.byKey(const ValueKey('r0c0')));
      await tester.pump();
      controller.applyFormat(
        controller.selection.range!,
        (f) => f.withBold(true),
      );

      await ctrl(tester, LogicalKeyboardKey.keyC);
      controller.selection.setHighlighted(1, 1);
      await ctrl(tester, LogicalKeyboardKey.keyV);

      expect(controller.cellAt(1, 1).value, 'a');
      expect(controller.formatAt(1, 1).bold, isTrue);
    });

    testWidgets('offers the formatting toolbar in theme colors ($name)', (
      tester,
    ) async {
      final controller = await pumpTab(tester, size);
      controller.selection.setHighlighted(0, 1);
      await tester.pump();
      final tokens = QuarkTokens.of(tester.element(find.byType(SheetTabView)));

      // No phone menu here: the scroller keeps the toolbar a row (#2770).
      expect(find.byKey(const ValueKey('format_menu')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('format_fill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('format_fill_2')));
      await tester.pumpAndSettle();

      expect(
        controller.formatAt(0, 1).fillColor,
        tokens.warning.withValues(alpha: fillAlpha).toARGB32(),
      );
      expect(tester.takeException(), isNull);
    });
  }

  // The control bar scrolls sideways on a phone, and a mouse user with no
  // wheel gets a chevron to reach the far end (#2770).
  testWidgets('a mouse gets a chevron that scrolls the control bar', (
    tester,
  ) async {
    await pumpTab(tester, const Size(360, 640));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 300));
    addTearDown(mouse.removePointer);
    await tester.pump();

    expect(find.byKey(const ValueKey('toolbar_scroll_left')), findsNothing);
    final before = tester.getTopLeft(find.byType(DataSheetControlBar)).dx;
    // Each bar has its own scroller; the control bar's is the first.
    await tester.tap(find.byKey(const ValueKey('toolbar_scroll_right')).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(DataSheetControlBar)).dx,
      lessThan(before),
    );
    expect(find.byKey(const ValueKey('toolbar_scroll_left')), findsOneWidget);
  });
}
