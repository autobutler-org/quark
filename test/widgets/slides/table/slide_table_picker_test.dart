import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/table/slide_table_picker.dart';
import 'package:quark/widgets/slides/table/slide_table_properties_section.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;
import '../../../support/text_scale.dart';

/// Insert > Table's picker and the properties panel's table section
/// (#1160): data in, callbacks out.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );

  Finder key(String k) => find.byKey(ValueKey(k));
  String readout(WidgetTester tester) =>
      tester.widget<Text>(key('slide_table_size_readout')).data!;

  late List<(String, int, int)> picks;
  Widget picker({int rows = 3, int columns = 3}) => SlideTablePicker(
    rows: rows,
    columns: columns,
    onDraw: (r, c) => picks.add(('draw', r, c)),
    onInsert: (r, c) => picks.add(('insert', r, c)),
  );

  setUp(() => picks = []);

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('picks a size by grid, steppers and buttons ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await pump(tester, picker());
      expect(readout(tester), '3 × 3 table');

      await tester.tap(key('slide_table_rows_more'));
      await tester.tap(key('slide_table_columns_less'));
      await tester.pump();
      expect(readout(tester), '4 × 2 table');
      await tester.tap(key('slide_table_insert'));
      await tester.tap(key('slide_table_draw'));
      expect(picks, [('insert', 4, 2), ('draw', 4, 2)]);

      await tester.tap(key('slide_table_grid_2_5'));
      expect(picks.last, ('draw', 2, 5));
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('hovering the grid lights and reads the size under it', (
    tester,
  ) async {
    await pump(tester, picker());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(key('slide_table_grid_6_7')));
    await tester.pump();
    expect(readout(tester), '6 × 7 table');
    expect(find.bySemanticsLabel('6 by 7 table'), findsOneWidget);
  });

  testWidgets('the steppers stop at one and at the most', (tester) async {
    await pump(tester, picker(rows: 1, columns: SlideTablePicker.maxSize));
    expect(
      tester.widget<QuarkBarIconButton>(key('slide_table_rows_less')).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<QuarkBarIconButton>(key('slide_table_columns_more'))
          .onPressed,
      isNull,
    );
    // Past the grid's eight, the grid lights its last square.
    expect(readout(tester), '1 × 20 table');
  });

  testWidgets('the grid is one button to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, picker());
    expect(
      tester.getSemantics(find.bySemanticsLabel('Table size')),
      matchesSemantics(
        label: 'Table size',
        value: '3 by 3',
        isButton: true,
        hasTapAction: true,
      ),
    );
    // A screen reader's double tap picks the size the grid reads.
    tester.semantics.tap(find.semantics.byLabel('Table size'));
    expect(picks, [('draw', 3, 3)]);
    handle.dispose();
  });

  testLargeText('the picker fits', (tester, size) async {
    await pump(tester, picker());
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  group('properties section', () {
    for (final (name, size) in [
      ('narrow', tap.narrowViewport),
      ('wide', tap.wideViewport),
    ]) {
      testWidgets('reads the size and switches the style ($name)', (
        tester,
      ) async {
        tap.setViewport(tester, size);
        final header = <bool>[];
        final banded = <bool>[];
        await pump(
          tester,
          SizedBox(
            width: 280,
            child: SlideTablePropertiesSection(
              rows: 1,
              columns: 4,
              headerRow: true,
              bandedRows: false,
              onHeaderRowChanged: header.add,
              onBandedRowsChanged: banded.add,
            ),
          ),
        );
        expect(find.text('1 row × 4 columns'), findsOneWidget);
        await tester.tap(key('slide_prop_table_header_row'));
        await tester.tap(key('slide_prop_table_banded_rows'));
        expect(header, [false]);
        expect(banded, [true]);
        await tap.expectTapTargetGuidelines(tester);
      });
    }

    testWidgets('a view-only deck takes no input', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 280,
          child: SlideTablePropertiesSection(
            rows: 3,
            columns: 3,
            headerRow: true,
            bandedRows: true,
          ),
        ),
      );
      expect(
        tester
            .widget<SwitchListTile>(key('slide_prop_table_header_row'))
            .onChanged,
        isNull,
      );
    });
  });
}
