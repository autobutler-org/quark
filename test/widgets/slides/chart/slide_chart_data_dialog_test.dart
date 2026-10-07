import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/slides/chart/slide_chart_data_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;
import '../../../support/text_scale.dart';

/// The chart's "Edit data" dialog (#1160): an editable grid of series by
/// categories, checked per cell, grown and shrunk within the chart limits,
/// filled from a pasted spreadsheet, and applied only on OK.
void main() {
  const grid = [
    ['', 'Revenue', 'Costs'],
    ['Q1', '12', '8'],
    ['Q2', '30', '9'],
  ];

  late List<List<List<String>>> applied;
  String? clipboard;
  Object? applyFailure;

  setUp(() {
    applied = [];
    clipboard = null;
    applyFailure = null;
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Taps OK, scrolling the dialog to it first.
  Future<void> ok(WidgetTester tester) async {
    await tester.ensureVisible(key('slide_chart_data_ok'));
    await tester.pumpAndSettle();
    await tester.tap(key('slide_chart_data_ok'));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool canPaste = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SlideChartDataDialog(
                    grid: grid,
                    onApply: (g) {
                      final failure = applyFailure;
                      if (failure != null) throw failure;
                      applied.add([
                        for (final row in g) [...row],
                      ]);
                    },
                    readClipboard: canPaste ? () async => clipboard : null,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('edits a value and applies the grid once on OK ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await open(tester);
      expect(key('slide_chart_data_dialog'), findsOneWidget);
      expect(find.text('Revenue'), findsOneWidget);
      await tester.enterText(key('slide_chart_cell_2_1'), '31');
      await tester.pump();
      expect(applied, isEmpty, reason: 'nothing changes until OK');
      await ok(tester);
      expect(applied, [
        [
          ['', 'Revenue', 'Costs'],
          ['Q1', '12', '8'],
          ['Q2', '31', '9'],
        ],
      ]);
      expect(key('slide_chart_data_dialog'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('meets the tap target guidelines ($name)', (tester) async {
      tap.setViewport(tester, size);
      await open(tester);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('a value that is not a number is flagged and keeps OK off', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(key('slide_chart_cell_1_2'), 'eight');
    await tester.pump();
    expect(find.text(Errors.chartValueNotNumber), findsOneWidget);
    expect(
      tester.widget<FilledButton>(key('slide_chart_data_ok')).onPressed,
      isNull,
    );
    await tester.enterText(key('slide_chart_cell_1_2'), '1,200');
    await tester.pump();
    expect(find.text(Errors.chartValueNotNumber), findsNothing);
    expect(
      tester.widget<FilledButton>(key('slide_chart_data_ok')).onPressed,
      isNotNull,
    );
  });

  testWidgets('adds and removes series and categories, never the last', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(key('slide_chart_add_series'));
    await tester.pump();
    expect(find.text('Series 3'), findsOneWidget);
    await tester.tap(key('slide_chart_add_category'));
    await tester.pump();
    expect(find.text('Category 3'), findsOneWidget);
    await tester.tap(key('slide_chart_remove_series_0'));
    await tester.pump();
    expect(find.text('Revenue'), findsNothing);
    await tester.tap(key('slide_chart_remove_category_0'));
    await tester.pump();
    expect(find.text('Q1'), findsNothing);
    await ok(tester);
    expect(applied.single, [
      ['', 'Costs', 'Series 3'],
      ['Q2', '9', '0'],
      ['Category 3', '0', '0'],
    ]);
  });

  testWidgets('the last series and category cannot be removed', (tester) async {
    await open(tester);
    await tester.tap(key('slide_chart_remove_series_1'));
    await tester.tap(key('slide_chart_remove_category_1'));
    await tester.pump();
    for (final k in [
      'slide_chart_remove_series_0',
      'slide_chart_remove_category_0',
    ]) {
      expect(tester.widget<QuarkBarIconButton>(key(k)).onPressed, isNull);
    }
  });

  testWidgets('Paste replaces the grid with a spreadsheet\'s cells', (
    tester,
  ) async {
    await open(tester);
    clipboard = '\tNorth\tSouth\nJan\t5\t7\nFeb\t6\t\n';
    await tester.tap(key('slide_chart_paste'));
    await tester.pumpAndSettle();
    expect(find.text('North'), findsOneWidget);
    expect(find.text('Revenue'), findsNothing);
    await ok(tester);
    expect(applied.single, [
      ['', 'North', 'South'],
      ['Jan', '5', '7'],
      ['Feb', '6', ''],
    ]);
  });

  testWidgets('a paste with no table, or past the limits, says so and '
      'keeps the grid', (tester) async {
    await open(tester);
    clipboard = 'hello';
    await tester.tap(key('slide_chart_paste'));
    await tester.pumpAndSettle();
    expect(find.text(Errors.chartPasteNoTable), findsOneWidget);
    clipboard = [
      ['', for (var i = 0; i < 51; i++) 'S$i'].join('\t'),
      ['Q1', for (var i = 0; i < 51; i++) '1'].join('\t'),
    ].join('\n');
    await tester.tap(key('slide_chart_paste'));
    await tester.pumpAndSettle();
    expect(find.text(Errors.chartTooLarge), findsOneWidget);
    expect(find.text('Revenue'), findsOneWidget);
  });

  testWidgets('without a clipboard, Paste is off', (tester) async {
    await open(tester, canPaste: false);
    expect(
      tester.widget<QuarkBarChip>(key('slide_chart_paste')).onPressed,
      isNull,
    );
  });

  testWidgets('a refused apply says why and stays open', (tester) async {
    applyFailure = ArgumentError('too big');
    await open(tester);
    await ok(tester);
    expect(find.text(Errors.chartTooLarge), findsOneWidget);
    expect(key('slide_chart_data_dialog'), findsOneWidget);
  });

  testWidgets('Cancel leaves the chart alone', (tester) async {
    await open(tester);
    await tester.enterText(key('slide_chart_cell_1_1'), '99');
    await tester.tap(key('slide_chart_data_cancel'));
    await tester.pumpAndSettle();
    expect(applied, isEmpty);
    expect(key('slide_chart_data_dialog'), findsNothing);
  });

  testLargeText('the dialog fits', (tester, size) async {
    await open(tester);
    expect(tester.takeException(), isNull);
  });
}
