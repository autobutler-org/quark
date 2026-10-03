import 'package:data_table/src/data_sheet/control_bar.dart';
import 'package:data_table/src/data_sheet/data_sheet.dart';
import 'package:data_table/src/data_sheet/data_sheet_clipboard.dart';
import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrow = Size(360, 640);
const _wide = Size(1280, 800);

/// A clipboard the test can read and seed, standing in for the system one.
class _FakeClipboard {
  String? text;

  DataSheetClipboard get clipboard => DataSheetClipboard(
        read: () async => text,
        write: (value) async => text = value,
      );
}

Future<(DataSheetController, _FakeClipboard)> _pump(
  WidgetTester tester,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = DataSheetController.fromTable(
    DataTable(
      List.generate(
        6,
        (r) => DataRow(List.generate(4, (c) => DataCell('$r,$c'))),
      ),
    ),
  );
  addTearDown(controller.dispose);
  final fake = _FakeClipboard();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            DataSheetControlBar(
              controller: controller,
              clipboard: fake.clipboard,
            ),
            Expanded(
              child: DataSheet(
                controller: controller,
                table: DataTable([]),
                clipboard: fake.clipboard,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return (controller, fake);
}

Finder _cell(int r, int c) => find.byKey(ValueKey('r${r}c$c'));

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _selectB2toC3(WidgetTester tester) async {
  await tester.tap(_cell(1, 1));
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

Future<void> _tapBar(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
    group('range clipboard ($name)', () {
      testWidgets('Ctrl+C copies the range as TSV, Ctrl+V pastes it', (
        tester,
      ) async {
        final (controller, fake) = await _pump(tester, size);
        await _selectB2toC3(tester);

        await _ctrl(tester, LogicalKeyboardKey.keyC);
        expect(fake.text, '1,1\t1,2\n2,1\t2,2');

        await tester.tap(_cell(4, 0));
        await tester.pump();
        await _ctrl(tester, LogicalKeyboardKey.keyV);

        expect(controller.cellAt(4, 0).value, '1,1');
        expect(controller.cellAt(5, 1).value, '2,2');
        expect(controller.selection.range!.label, 'A5:B6');

        await _ctrl(tester, LogicalKeyboardKey.keyZ);
        expect(controller.cellAt(4, 0).value, '4,0');
        expect(controller.cellAt(5, 1).value, '5,1');
      });

      testWidgets('Ctrl+X copies then clears the range in one undo step', (
        tester,
      ) async {
        final (controller, fake) = await _pump(tester, size);
        await _selectB2toC3(tester);

        await _ctrl(tester, LogicalKeyboardKey.keyX);
        expect(fake.text, '1,1\t1,2\n2,1\t2,2');
        expect(controller.cellAt(1, 1).value, '');
        expect(controller.cellAt(2, 2).value, '');

        await _ctrl(tester, LogicalKeyboardKey.keyZ);
        expect(controller.cellAt(1, 1).value, '1,1');
        expect(controller.cellAt(2, 2).value, '2,2');
      });

      testWidgets('Delete clears the whole range', (tester) async {
        final (controller, _) = await _pump(tester, size);
        await _selectB2toC3(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        for (final (r, c) in [(1, 1), (1, 2), (2, 1), (2, 2)]) {
          expect(controller.cellAt(r, c).value, '', reason: 'r${r}c$c');
        }
        expect(controller.cellAt(0, 0).value, '0,0');
      });

      testWidgets('pasting from Google Sheets grows the sheet', (tester) async {
        final (controller, fake) = await _pump(tester, size);
        fake.text = 'a\t"multi\nline"\r\nb\tc\r\n';
        // Tap first so the sheet has keyboard focus.
        await tester.tap(_cell(0, 0));
        controller.selection.goTo(5, 3);
        await tester.pump();

        await _ctrl(tester, LogicalKeyboardKey.keyV);

        expect(controller.rowCount, 7);
        expect(controller.colCount, 5);
        expect(controller.cellAt(5, 4).value, 'multi\nline');
        expect(controller.cellAt(6, 4).value, 'c');
      });

      testWidgets('Ctrl+D fills the top row down the range', (tester) async {
        final (controller, _) = await _pump(tester, size);
        await _selectB2toC3(tester);

        await _ctrl(tester, LogicalKeyboardKey.keyD);

        expect(controller.cellAt(2, 1).value, '1,1');
        expect(controller.cellAt(2, 2).value, '1,2');
        expect(controller.cellAt(3, 1).value, '3,1', reason: 'outside range');
      });

      testWidgets('control bar copy, cut, paste and clear act on the range', (
        tester,
      ) async {
        final (controller, fake) = await _pump(tester, size);
        await _selectB2toC3(tester);

        for (final key in [
          'data_sheet_copy',
          'data_sheet_cut',
          'data_sheet_paste',
          'data_sheet_clear_range',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        }
        expect(find.byTooltip('Copy'), findsOneWidget);
        expect(find.byTooltip('Cut'), findsOneWidget);
        expect(find.byTooltip('Paste'), findsOneWidget);
        expect(find.byTooltip('Clear selected cells'), findsOneWidget);

        await _tapBar(tester, 'data_sheet_copy');
        expect(fake.text, '1,1\t1,2\n2,1\t2,2');

        await _tapBar(tester, 'data_sheet_clear_range');
        expect(controller.cellAt(1, 1).value, '');

        await _tapBar(tester, 'data_sheet_paste');
        expect(controller.cellAt(1, 1).value, '1,1');
        expect(controller.cellAt(2, 2).value, '2,2');

        await _tapBar(tester, 'data_sheet_cut');
        expect(controller.cellAt(1, 1).value, '');
        expect(fake.text, '1,1\t1,2\n2,1\t2,2');
      });
    });
  }

  testWidgets('without an app clipboard, copy and paste stay in memory', (
    tester,
  ) async {
    final controller = DataSheetController.fromTable(
      DataTable([
        DataRow([DataCell('a'), DataCell('')]),
      ]),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DataSheet(controller: controller, table: DataTable([])),
        ),
      ),
    );
    await tester.tap(_cell(0, 0));
    await tester.pump();
    await _ctrl(tester, LogicalKeyboardKey.keyC);
    await tester.tap(_cell(0, 1));
    await tester.pump();
    await _ctrl(tester, LogicalKeyboardKey.keyV);
    expect(controller.cellAt(0, 1).value, 'a');
  });
}
