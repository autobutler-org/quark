import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/chart/slide_chart_kind_preview.dart';
import 'package:quark/widgets/slides/chart/slide_chart_picker.dart';
import 'package:quark/widgets/slides/chart/slide_chart_properties_section.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;
import '../../../support/text_scale.dart';

/// Insert > Chart's picker and the properties panel's chart section
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

  late List<(String, ChartKind)> picks;
  Widget picker({ChartKind kind = ChartKind.bar}) => SlideChartPicker(
    kind: kind,
    onDraw: (k) => picks.add(('draw', k)),
    onInsert: (k) => picks.add(('insert', k)),
  );

  setUp(() => picks = []);

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('offers the five kinds with previews, then draws or '
        'inserts the one picked ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pump(tester, picker());
      for (final kind in ChartKind.values) {
        expect(key('slide_chart_pick_${kind.name}'), findsOneWidget);
        expect(find.text(chartKindName(kind)), findsOneWidget);
      }
      expect(find.byType(SlideChartKindPreview), findsNWidgets(5));

      await tester.tap(key('slide_chart_insert'));
      expect(picks, [('insert', ChartKind.bar)]);
      await tester.tap(key('slide_chart_pick_pie'));
      await tester.pump();
      await tester.tap(key('slide_chart_draw'));
      await tester.tap(key('slide_chart_insert'));
      expect(picks.skip(1), [
        ('draw', ChartKind.pie),
        ('insert', ChartKind.pie),
      ]);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('starts at the kind given, read as selected', (tester) async {
    await pump(tester, picker(kind: ChartKind.area));
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(key('slide_chart_pick_area')),
      matchesSemantics(
        label: 'Area chart',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
    await tester.tap(key('slide_chart_draw'));
    expect(picks, [('draw', ChartKind.area)]);
  });

  testLargeText('the picker fits', (tester, size) async {
    await pump(tester, picker());
    expect(tester.takeException(), isNull);
  });

  group('properties section', () {
    final chart = ChartElement(
      id: 'c',
      frame: ElementFrame(x: 0, y: 0, width: 600, height: 400),
      kind: ChartKind.line,
      data: SlideDocumentController.sampleChartData(ChartKind.line),
      options: const ChartOptions(title: 'Sales'),
    );

    testWidgets('reads the kind and data, and saves a new title', (
      tester,
    ) async {
      final titles = <String>[];
      await pump(
        tester,
        SizedBox(
          width: 280,
          child: SlideChartPropertiesSection(
            chart: chart,
            onTitleChanged: titles.add,
          ),
        ),
      );
      expect(find.text('Line chart, 3 series × 4 categories'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
      await tester.enterText(key('slide_prop_chart_title'), 'Costs ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(titles, ['Costs']);
    });

    testWidgets('view only shows the title without taking input', (
      tester,
    ) async {
      await pump(
        tester,
        SizedBox(width: 280, child: SlideChartPropertiesSection(chart: chart)),
      );
      expect(
        tester.widget<TextField>(key('slide_prop_chart_title')).readOnly,
        isTrue,
      );
    });
  });
}
