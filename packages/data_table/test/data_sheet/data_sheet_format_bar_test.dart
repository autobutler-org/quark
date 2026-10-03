import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
// Material ships its own DataTable/DataRow/DataCell — this package's models
// win here.
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter_test/flutter_test.dart';

const _narrow = Size(360, 640);
const _wide = Size(1280, 800);

Future<DataSheetController> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = DataSheetController.fromTable(
    DataTable([
      DataRow([DataCell('1234.5'), DataCell('text'), DataCell('=A1*2')]),
      DataRow([DataCell('0.25'), DataCell('b'), DataCell('c')]),
      DataRow([DataCell('45658'), DataCell('e'), DataCell('f')]),
    ]),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            DataSheetFormatBar(controller: controller),
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

/// The text widget inside cell [r],[c].
Text _cellText(WidgetTester tester, int r, int c) => tester.widget<Text>(
      find.descendant(of: _key('r${r}c$c'), matching: find.byType(Text)),
    );

/// Opens the format menu on a narrow screen; a no-op on a wide one.
Future<void> _openMenuIfNarrow(WidgetTester tester, Size size) async {
  if (size != _narrow) return;
  await tester.tap(_key('format_menu'));
  await tester.pumpAndSettle();
}

/// Opens [submenu]: a toolbar menu button when wide, a submenu of the format
/// menu when narrow.
Future<void> _openSubmenu(
  WidgetTester tester,
  Size size,
  String submenu,
) async {
  await _openMenuIfNarrow(tester, size);
  await tester.tap(_key(submenu));
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
    group('DataSheetFormatBar ($name)', () {
      testWidgets('is disabled until a cell is selected', (tester) async {
        final c = await _pump(tester, size);
        final control =
            size == _narrow ? _key('format_menu') : _key('format_bold');
        expect(control, findsOneWidget);
        await tester.tap(control, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(c.canUndo, isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('bolds the whole range as one undo step', (tester) async {
        final c = await _pump(tester, size);
        c.selection.selectRange(0, 0, 1, 1);
        await tester.pump();
        await _openMenuIfNarrow(tester, size);
        await tester.tap(_key('format_bold'));
        await tester.pumpAndSettle();
        for (final (r, col) in [(0, 0), (0, 1), (1, 0), (1, 1)]) {
          expect(c.formatAt(r, col).bold, isTrue);
        }
        expect(c.formatAt(2, 2).bold, isFalse);
        expect(_cellText(tester, 0, 0).style?.fontWeight, FontWeight.bold);
        c.undo();
        expect(c.formats, isEmpty);
      });

      testWidgets('sets a fill and a text color from the palette', (
        tester,
      ) async {
        final c = await _pump(tester, size);
        c.selection.setHighlighted(0, 1);
        await tester.pump();
        await _openSubmenu(tester, size, 'format_fill');
        await tester.tap(_key('format_fill_3'));
        await tester.pumpAndSettle();
        expect(
          c.formatAt(0, 1).fillColor,
          DataSheetPalette.fill[3].color.toARGB32(),
        );
        await _openSubmenu(tester, size, 'format_text_color');
        await tester.tap(_key('format_text_color_1'));
        await tester.pumpAndSettle();
        expect(
          _cellText(tester, 0, 1).style?.color,
          DataSheetPalette.text[1].color,
        );
        await _openSubmenu(tester, size, 'format_text_color');
        await tester.tap(_key('format_text_color_none'));
        await tester.pumpAndSettle();
        expect(c.formatAt(0, 1).textColor, isNull);
      });

      testWidgets('aligns, and choosing it again restores the default', (
        tester,
      ) async {
        final c = await _pump(tester, size);
        c.selection.setHighlighted(0, 1);
        await tester.pump();
        Future<void> center() async {
          if (size == _narrow) await _openSubmenu(tester, size, 'format_align');
          await tester.tap(_key('format_align_center'));
          await tester.pumpAndSettle();
        }

        await center();
        expect(_cellText(tester, 0, 1).textAlign, TextAlign.center);
        await center();
        expect(c.formatAt(0, 1).align, isNull);
      });

      testWidgets('number formats change what cells show, not their values', (
        tester,
      ) async {
        final c = await _pump(tester, size);
        c.selection.selectRange(0, 0, 0, 2);
        await tester.pump();
        await _openSubmenu(tester, size, 'format_number');
        await tester.tap(_key('format_number_currency'));
        await tester.pumpAndSettle();
        expect(find.text(r'$1,234.50'), findsOneWidget);
        expect(find.text(r'$2,469.00'), findsOneWidget);
        expect(find.text('text'), findsOneWidget);
        expect(c.cellAt(0, 0).value, '1234.5');
        expect(c.cellAt(0, 2).value, '=A1*2');

        await _openMenuIfNarrow(tester, size);
        await tester.tap(_key('format_decimals_decrease'));
        await tester.pumpAndSettle();
        expect(find.text(r'$1,234.5'), findsOneWidget);

        c.selection.setHighlighted(1, 0);
        await tester.pump();
        await _openSubmenu(tester, size, 'format_number');
        await tester.tap(_key('format_number_percent'));
        await tester.pumpAndSettle();
        expect(find.text('25.00%'), findsOneWidget);

        c.selection.setHighlighted(2, 0);
        await tester.pump();
        await _openSubmenu(tester, size, 'format_number');
        await tester.tap(_key('format_number_date'));
        await tester.pumpAndSettle();
        expect(find.text('2025-01-01'), findsOneWidget);
      });

      testWidgets('clear formatting keeps the values', (tester) async {
        final c = await _pump(tester, size);
        c.selection.setHighlighted(0, 0);
        c.applyFormat(
          c.selection.range!,
          (f) => f.withBold(true).withNumberFormat(CellNumberFormat.currency),
        );
        await tester.pump();
        expect(find.text(r'$1,234.50'), findsOneWidget);
        await _openMenuIfNarrow(tester, size);
        await tester.tap(_key('format_clear'));
        await tester.pumpAndSettle();
        expect(c.formats, isEmpty);
        expect(_cellText(tester, 0, 0).data, '1234.5');
      });

      testWidgets('every toolbar control has a tooltip', (tester) async {
        final c = await _pump(tester, size);
        c.selection.setHighlighted(0, 0);
        await tester.pump();
        final keys = size == _narrow
            ? ['format_menu']
            : [
                'format_bold',
                'format_italic',
                'format_text_color',
                'format_fill',
                'format_align_left',
                'format_align_center',
                'format_align_right',
                'format_number',
                'format_decimals_decrease',
                'format_decimals_increase',
                'format_clear',
              ];
        for (final key in keys) {
          expect(
            find.ancestor(of: _key(key), matching: find.byType(Tooltip)),
            findsOneWidget,
            reason: key,
          );
        }
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('a fill shows under the cell text', (tester) async {
    final c = await _pump(tester, _wide);
    c.applyFormat(
      const CellRange(top: 1, left: 1, bottom: 1, right: 1),
      (f) => f.withFillColor(0xFF10B981),
    );
    await tester.pump();
    final box = tester.widget<Container>(
      find.descendant(of: _key('r1c1'), matching: find.byType(Container)),
    );
    expect(
      (box.decoration as BoxDecoration).color,
      const Color(0xFF10B981),
    );
  });

  testWidgets('a toggle shows the highlighted cell\'s state', (tester) async {
    final c = await _pump(tester, _wide);
    c.applyFormat(
      const CellRange(top: 0, left: 0, bottom: 0, right: 0),
      (f) => f.withItalic(true),
    );
    c.selection.setHighlighted(0, 0);
    await tester.pump();
    expect(
      tester.widget<IconButton>(_key('format_italic')).isSelected,
      isTrue,
    );
    c.selection.setHighlighted(0, 1);
    await tester.pump();
    expect(
      tester.widget<IconButton>(_key('format_italic')).isSelected,
      isFalse,
    );
  });

  testWidgets('decimal steps are disabled for automatic and date', (
    tester,
  ) async {
    final c = await _pump(tester, _wide);
    c.selection.setHighlighted(0, 0);
    await tester.pump();
    expect(
      tester.widget<IconButton>(_key('format_decimals_increase')).onPressed,
      isNull,
    );
  });
}
