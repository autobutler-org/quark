import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:data_table/src/data_sheet/cell/cell.dart';
import 'package:data_table/src/data_sheet/cell/editable_cell.dart';
import 'package:flutter/gestures.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrow = Size(360, 640);
const _wide = Size(1280, 800);

/// A 6x4 sheet of numbers, with [cells] overriding some by (row, col).
DataSheetController _makeController(
    [Map<(int, int), String> cells = const {}]) {
  return DataSheetController.fromTable(
    DataTable(
      List.generate(
        6,
        (r) => DataRow(
          List.generate(4, (c) => DataCell(cells[(r, c)] ?? '${r + c}')),
        ),
      ),
    ),
  );
}

Future<DataSheetController> _pumpSheet(
  WidgetTester tester,
  Size size, {
  Map<(int, int), String> cells = const {},
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = _makeController(cells);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: DataSheet(controller: controller, table: DataTable([])),
      ),
    ),
  );
  return controller;
}

Finder _cell(int r, int c) => find.byKey(ValueKey('r${r}c$c')).first;

Finder get _cellEditor => find.descendant(
      of: find.byType(EditableCell),
      matching: find.byType(TextField),
    );

Finder get _bar => find.byKey(const ValueKey('data_sheet_formula_field'));

Finder _suggestion(String name) =>
    find.byKey(ValueKey('formula_suggestion_$name'));

Finder get _suggestions => find.byKey(const ValueKey('formula_suggestions'));

/// Opens the cell at ([r], [c]) for editing and types [text] into it.
Future<void> _editCell(
  WidgetTester tester,
  int r,
  int c,
  String text,
) async {
  await tester.tap(_cell(r, c));
  await tester.pump();
  await tester.tap(_cell(r, c));
  await tester.pumpAndSettle();
  await tester.enterText(_cellEditor, text);
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// Drags with a mouse from cell ([r0], [c0]) to cell ([r1], [c1]).
Future<void> _mouseDrag(
  WidgetTester tester,
  (int, int) from,
  (int, int) to,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_cell(from.$1, from.$2)),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(tester.getCenter(_cell(to.$1, to.$2)));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
    group('function autocomplete ($name)', () {
      testWidgets('typing a name lists matching functions', (tester) async {
        await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=SU');

        expect(_suggestions, findsOneWidget);
        expect(_suggestion('SUBSTITUTE'), findsOneWidget);
        expect(_suggestion('SUM'), findsOneWidget);
        expect(_suggestion('AVERAGE'), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp(r'^SUM\(value1')),
          findsOneWidget,
        );
      });

      testWidgets('rows are at least 48 pixels tall and fit the screen', (
        tester,
      ) async {
        await _pumpSheet(tester, size);
        await _editCell(tester, 1, 2, '=CO');

        for (final name in ['CONCAT', 'COUNT', 'COUNTA', 'COUNTIF']) {
          expect(tester.getSize(_suggestion(name)).height,
              greaterThanOrEqualTo(48));
        }
        final list = tester.getRect(_suggestions);
        expect(list.left, greaterThanOrEqualTo(0));
        expect(list.right, lessThanOrEqualTo(size.width));
        expect(list.bottom, lessThanOrEqualTo(size.height));
      });

      testWidgets('arrows move and Enter accepts, opening the parenthesis', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=1+su');

        await _key(tester, LogicalKeyboardKey.arrowDown);
        await _key(tester, LogicalKeyboardKey.enter);

        expect(controller.activeCellEditingController.text, '=1+SUM(');
        expect(controller.selection.activeRow, 0, reason: 'still editing');
        expect(_suggestions, findsNothing);
      });

      testWidgets('Tab accepts the highlighted function', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=AV');

        await _key(tester, LogicalKeyboardKey.tab);

        expect(controller.activeCellEditingController.text, '=AVERAGE(');
        expect(controller.selection.activeRow, 0);
      });

      testWidgets('tapping a suggestion accepts it', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=MA');

        await tester.tap(_suggestion('MAX'));
        await tester.pumpAndSettle();

        expect(controller.activeCellEditingController.text, '=MAX(');
        expect(controller.selection.activeRow, 0);
      });

      testWidgets('Escape closes the list and keeps the edit', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=IS');
        expect(_suggestions, findsOneWidget);

        await _key(tester, LogicalKeyboardKey.escape);

        expect(_suggestions, findsNothing);
        expect(controller.selection.activeRow, 0);
        expect(controller.activeCellEditingController.text, '=IS');

        // A second Escape cancels the edit as usual.
        await _key(tester, LogicalKeyboardKey.escape);
        expect(controller.selection.activeRow, -1);
        expect(controller.cellAt(0, 2).value, '2');
      });

      testWidgets('the formula bar offers the same list', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(_cell(0, 2));
        await tester.pump();
        await tester.tap(_bar);
        await tester.pumpAndSettle();
        await tester.enterText(_bar, '=IF');
        await tester.pumpAndSettle();

        expect(_suggestion('IF'), findsOneWidget);
        expect(_suggestion('IFERROR'), findsOneWidget);
        await _key(tester, LogicalKeyboardKey.enter);

        expect(controller.activeCellEditingController.text, '=IF(');
        expect(controller.selection.activeRow, 0);
      });
    });

    group('reference picking ($name)', () {
      testWidgets('clicking a cell writes its reference at the caret', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=SUM(');

        await tester.tap(_cell(1, 0));
        await tester.pumpAndSettle();
        expect(controller.activeCellEditingController.text, '=SUM(A2');
        expect(controller.selection.activeRow, 0, reason: 'still editing');

        // Clicking again moves the reference rather than adding one.
        await tester.tap(_cell(2, 1));
        await tester.pumpAndSettle();
        expect(controller.activeCellEditingController.text, '=SUM(B3');
      });

      testWidgets('dragging writes a range and outlines it in its color', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=SUM(');

        await _mouseDrag(tester, (1, 0), (3, 1));

        expect(controller.activeCellEditingController.text, '=SUM(A2:B4');
        final color = kFormulaReferencePalette.first;
        expect(controller.activeRefColors[(1, 0)], color);
        expect(controller.activeRefColors[(3, 1)], color);
        expect(controller.activeRefColors.containsKey((0, 0)), isFalse);
        final cell = tester.widget<Cell>(
          find.byWidgetPredicate(
            (w) => w is Cell && w.key == const ValueKey('r2c1'),
          ),
        );
        expect(cell.referenceColor, color);
      });

      testWidgets('where no reference fits, a click commits and moves', (
        tester,
      ) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, '=A1+A2');

        await tester.tap(_cell(3, 1));
        await tester.pumpAndSettle();

        expect(controller.cellAt(0, 2).value, '=A1+A2');
        expect(controller.displayValueAt(0, 2), '1');
        expect(controller.selection.activeRow, -1);
        expect(controller.selection.highlightedRow, 3);
        expect(controller.selection.highlightedCol, 1);
      });

      testWidgets('a plain edit still commits on a click', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await _editCell(tester, 0, 2, 'hello');

        await tester.tap(_cell(2, 0));
        await tester.pumpAndSettle();

        expect(controller.cellAt(0, 2).value, 'hello');
        expect(controller.selection.activeRow, -1);
      });

      testWidgets('picking while typing in the formula bar', (tester) async {
        final controller = await _pumpSheet(tester, size);
        await tester.tap(_cell(0, 2));
        await tester.pump();
        await tester.tap(_bar);
        await tester.pumpAndSettle();
        await tester.enterText(_bar, '=A1*');
        await tester.pumpAndSettle();

        await tester.tap(_cell(2, 1));
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(_bar).controller!.text, '=A1*B3');
        expect(controller.activeCellEditingController.text, '=A1*B3');
        expect(controller.activeRefColors[(2, 1)], kFormulaReferencePalette[1]);

        await _key(tester, LogicalKeyboardKey.enter);
        expect(controller.cellAt(0, 2).value, '=A1*B3');
        expect(controller.displayValueAt(0, 2), '0');
      });
    });

    group('error display ($name)', () {
      const cells = {
        (0, 0): '=1/0',
        (0, 1): '=TOTAL(1)',
        (0, 2): '=A1+1',
        (1, 1): '=1 + !',
      };

      testWidgets('errors show as chips with the reason attached', (
        tester,
      ) async {
        await _pumpSheet(tester, size, cells: cells);

        expect(find.byKey(const ValueKey('r0c0_error')), findsOneWidget);
        expect(find.byKey(const ValueKey('r0c1_error')), findsOneWidget);
        expect(find.byKey(const ValueKey('r0c2_error')), findsOneWidget);
        expect(find.byKey(const ValueKey('r1c0_error')), findsNothing);
        expect(find.text('#DIV/0!'), findsNWidgets(2));
        expect(find.text('#NAME?'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Error #DIV/0!: Division by zero'),
          findsNWidgets(2),
        );
        expect(
          find.bySemanticsLabel('Error #NAME?: Unknown function TOTAL'),
          findsOneWidget,
        );
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(
            of: find.text('#NAME?'),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, '#NAME? Unknown function TOTAL');
      });

      testWidgets('the formula bar spells out the selected error', (
        tester,
      ) async {
        await _pumpSheet(tester, size, cells: cells);
        expect(find.byKey(const ValueKey('data_sheet_formula_error')),
            findsNothing);

        await tester.tap(_cell(1, 1));
        await tester.pump();

        final note = find.byKey(const ValueKey('data_sheet_formula_error'));
        expect(note, findsOneWidget);
        expect(
          find.descendant(
            of: note,
            matching:
                find.text("Couldn't read the formula: Unexpected character: !"),
          ),
          findsOneWidget,
        );

        await tester.tap(_cell(1, 0));
        await tester.pump();
        expect(find.byKey(const ValueKey('data_sheet_formula_error')),
            findsNothing);
      });
    });
  }

  group('large text', () {
    testWidgets('suggestions and error chips survive 2x text on a phone', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        _narrow,
        cells: {(0, 0): '=1/0'},
        textScale: 2,
      );
      expect(find.byKey(const ValueKey('r0c0_error')), findsOneWidget);

      await _editCell(tester, 0, 1, '=CO');

      expect(tester.takeException(), isNull);
      expect(_suggestion('CONCAT'), findsOneWidget);
      final list = tester.getRect(_suggestions);
      expect(list.left, greaterThanOrEqualTo(0));
      expect(list.right, lessThanOrEqualTo(_narrow.width));
      expect(list.bottom, lessThanOrEqualTo(_narrow.height));
      expect(
        tester.getSize(_suggestion('CONCAT')).height,
        greaterThanOrEqualTo(48),
      );
    });
  });
}
