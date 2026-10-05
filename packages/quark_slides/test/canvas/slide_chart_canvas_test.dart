import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/canvas_harness.dart';
import '../support/chart_sample.dart';

/// A 16:9 deck with one slide `s` holding [sampleChart] (`chart`), in
/// [theme].
Presentation chartDeck({SlideTheme? theme, ChartElement? chart}) =>
    Presentation(
      theme: theme,
      slides: [
        Slide(id: 's', elements: [chart ?? sampleChart()]),
      ],
    );

/// The bar of series 0 on [sampleChart] uses a literal color, so series 1
/// — `accent2` — is the one a theme recolors.
Color accent2Of(SlideTheme theme) => Color(theme.colors[ThemeColor.accent2]);

void main() {
  late SlideDocumentNotifier doc;
  late SlideChartEditingController charts;
  setUp(() {
    doc = SlideDocumentNotifier(chartDeck(theme: SlideThemes.light));
    charts = SlideChartEditingController();
  });
  tearDown(() {
    doc.dispose();
    charts.dispose();
  });

  ChartElement chart([String id = 'chart']) =>
      doc.presentation.slideById('s')!.findElement(id)! as ChartElement;

  Finder chartPaint() => find.descendant(
        of: elementKey('chart'),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is SlideChartPainter,
        ),
      );

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    SlideCanvasInteraction interaction = SlideCanvasInteraction.editable,
  }) =>
      pumpCanvas(
        tester,
        doc,
        size: size,
        textScale: textScale,
        chartEditing: charts,
        interaction: interaction,
      );

  group('drawing', () {
    testBothViewports('paints the chart in its frame', (tester, size) async {
      await pump(tester, size);
      expect(chartPaint(), findsOne);
      final rect = tester.getRect(elementKey('chart'));
      final expected = Rect.fromPoints(
        slideToGlobal(tester, const Offset(360, 200)),
        slideToGlobal(tester, const Offset(1560, 900)),
      );
      expect(rect.left, closeTo(expected.left, 0.01));
      expect(rect.width, closeTo(expected.width, 0.01));
      expect(
        tester.renderObject(chartPaint()),
        paints..rect(color: const Color(0xFF224488)),
      );
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a 200% text scale changes nothing',
        (tester, size) async {
      await pump(tester, size, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(chartPaint(), findsOne);
    });

    testWidgets('theme roles resolve as it paints', (tester) async {
      await pump(tester, wideViewport);
      expect(
        tester.renderObject(chartPaint()),
        // The legend's swatches, series by series.
        paints
          ..rect(color: const Color(0xFF224488))
          ..rect(color: accent2Of(SlideThemes.light)),
      );
      doc.controller.setTheme(SlideThemes.warm);
      await tester.pump();
      expect(accent2Of(SlideThemes.warm), isNot(accent2Of(SlideThemes.light)));
      expect(
        tester.renderObject(chartPaint()),
        paints
          ..rect(color: const Color(0xFF224488))
          ..rect(color: accent2Of(SlideThemes.warm)),
      );
    });

    testBothViewports('every kind paints, with odd data and tiny frames',
        (tester, size) async {
      for (final kind in ChartKind.values) {
        for (final data in [
          sampleChart().data,
          ChartData(),
          ChartData(
            categories: const ['a', 'b', 'c'],
            series: [
              ChartSeries(name: 'neg', values: const [-5, 0, 7]),
            ],
          ),
          ChartData(
            categories: [for (var i = 0; i < 60; i++) 'Category $i'],
            series: [
              ChartSeries(values: [for (var i = 0; i < 60; i++) i * 1.5]),
            ],
          ),
        ]) {
          for (final frame in [
            sampleChart().frame,
            ElementFrame(x: 10, y: 10, width: 30, height: 20),
          ]) {
            doc.controller.load(chartDeck(
              chart:
                  sampleChart().copyWith(kind: kind, data: data, frame: frame),
            ));
            await pump(tester, size);
            expect(tester.takeException(), isNull,
                reason: '$kind ${data.categories.length} $frame');
          }
        }
      }
    });

    testWidgets('a pie paints a slice per positive value', (tester) async {
      doc.controller.load(chartDeck(
        theme: SlideThemes.light,
        chart: sampleChart().copyWith(kind: ChartKind.pie),
      ));
      await pump(tester, wideViewport);
      expect(
        tester.renderObject(chartPaint()),
        paints
          ..arc(color: const Color(0xFF224488))
          ..arc(color: accent2Of(SlideThemes.light))
          ..arc(color: Color(SlideThemes.light.colors[ThemeColor.accent3])),
      );
    });
  });

  group('editing as an element', () {
    testBothViewports('selects, moves and resizes with the handles',
        (tester, size) async {
      await pump(tester, size);
      await tester.tap(elementKey('chart'));
      await tester.pump();
      expect(harness(tester).selection, {'chart'});
      expect(handleKey(SlideHandle.bottomRight), findsOne);
      await tester.drag(elementKey('chart'), const Offset(40, 0));
      await tester.pump();
      expect(chart().frame.x, greaterThan(360));
      final moved = chart().frame;
      await tester.drag(
          handleKey(SlideHandle.bottomRight), const Offset(-30, -30));
      await tester.pump();
      expect(chart().frame.width, lessThan(moved.width));
      expect(chart().data, sampleChart().data);
      expect(undoAll(doc), 2);
    });

    testWidgets('Delete removes it and undo brings it back', (tester) async {
      await pump(tester, wideViewport);
      await tester.tap(elementKey('chart'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(doc.presentation.slides.single.elements, isEmpty);
      doc.controller.undo();
      await tester.pump();
      expect(elementKey('chart'), findsOne);
    });
  });

  group('screen reader', () {
    testWidgets('reads a summary, and the data as its value', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, wideViewport);
      const summary = 'Bar chart titled Sales, 2 series, 3 categories; '
          'highest value 42 in Q3';
      expect(find.bySemanticsLabel(summary), findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel(summary)),
        isSemantics(
          value: 'Q1: Revenue 12, Costs 8. Q2: Revenue 30, Costs 12.5. '
              'Q3: Revenue 42, Costs 20.',
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel(summary));
      await tester.pump();
      expect(harness(tester).selection, {'chart'});
      handle.dispose();
    });
  });

  group('the chart tool', () {
    testBothViewports('a click places a sample chart and selects it',
        (tester, size) async {
      doc.controller.load(Presentation(slides: [Slide(id: 's')]));
      await pump(tester, size);
      harness(tester).useTool(const SlideCanvasTool.chart(ChartKind.line));
      await tester.pump();
      await tester.tapAt(slideToGlobal(tester, const Offset(100, 100)));
      await tester.pump();
      final inserted =
          doc.presentation.slides.single.elements.single as ChartElement;
      expect(inserted.kind, ChartKind.line);
      expect(inserted.frame.x, closeTo(100, 1));
      expect(inserted.frame.width, doc.controller.defaultChartSize.width);
      expect(harness(tester).selection, {inserted.id});
      expect(harness(tester).tool, SlideCanvasTool.select);
      expect(undoAll(doc), 1);
    });

    testWidgets('a drag sizes it', (tester) async {
      doc.controller.load(Presentation(slides: [Slide(id: 's')]));
      await pump(tester, wideViewport);
      harness(tester).useTool(const SlideCanvasTool.chart(ChartKind.pie));
      await tester.pump();
      final start = slideToGlobal(tester, const Offset(200, 200));
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(slideToGlobal(tester, const Offset(500, 400)));
      await gesture.moveTo(slideToGlobal(tester, const Offset(800, 600)));
      await gesture.up();
      await tester.pump();
      final inserted =
          doc.presentation.slides.single.elements.single as ChartElement;
      expect(inserted.frame.width, closeTo(600, 2));
      expect(inserted.frame.height, closeTo(400, 2));
    });
  });

  group('SlideChartEditingController', () {
    testWidgets('follows the selected chart and sends one-step commands',
        (tester) async {
      var notified = 0;
      charts.addListener(() => notified++);
      await pump(tester, wideViewport);
      expect(charts.hasChart, isFalse);
      await tester.tap(elementKey('chart'));
      await tester.pump();
      await tester.pump();
      expect(charts.hasChart, isTrue);
      expect(charts.canEdit, isTrue);
      expect(notified, greaterThan(0));
      expect(charts.grid!.first, ['', 'Revenue', 'Costs']);

      charts.setKind(ChartKind.area);
      charts.setOptions(title: 'Totals', showLegend: false);
      charts.addSeries(name: 'Tax');
      charts.removeSeries(0);
      charts.setColors(const [SlideColor.theme(ThemeColor.accent6)]);
      charts.setDataGrid([
        ['', 'A'],
        ['x', '3'],
      ]);
      await tester.pump();
      expect(chart().kind, ChartKind.area);
      expect(chart().options.title, 'Totals');
      expect(chart().data.toGrid(), [
        ['', 'A'],
        ['x', '3'],
      ]);
      expect(chart().colors, const [SlideColor.theme(ThemeColor.accent6)]);
      expect(undoAll(doc), 6);

      // Deselecting lets go of the chart.
      await tester.tapAt(slideToGlobal(tester, const Offset(50, 1000)));
      await tester.pump();
      await tester.pump();
      expect(charts.hasChart, isFalse);
    });

    testWidgets('cannot remove the only series', (tester) async {
      doc.controller.load(chartDeck(
        chart: sampleChart().copyWith(
            kind: ChartKind.pie,
            data: ChartData(
              categories: const ['a'],
              series: [
                ChartSeries(values: const [1])
              ],
            )),
      ));
      await pump(tester, wideViewport);
      harness(tester).select({'chart'});
      await tester.pump();
      expect(charts.canRemoveSeries, isFalse);
      charts.removeSeries(0);
      expect(doc.controller.canUndo, isFalse);
    });

    testWidgets('selectOnly reports the chart but edits nothing',
        (tester) async {
      await pump(
        tester,
        wideViewport,
        interaction: SlideCanvasInteraction.selectOnly,
      );
      await tester.tap(elementKey('chart'));
      await tester.pump();
      expect(charts.hasChart, isTrue);
      expect(charts.canEdit, isFalse);
      charts.setKind(ChartKind.pie);
      charts.addSeries();
      charts.setOptions(title: 'x');
      expect(doc.controller.canUndo, isFalse);
      expect(handleKey(SlideHandle.bottomRight), findsNothing);
    });
  });
}
