import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/chart_sample.dart';

/// A 1920×1080 deck with one slide `s` holding [sampleChart] (`chart`) and
/// a shape `box`.
Presentation deck() => Presentation(
      slides: [
        Slide(
          id: 's',
          elements: [
            sampleChart(),
            ShapeElement(
              id: 'box',
              frame: ElementFrame(x: 0, y: 0, width: 10, height: 10),
            ),
          ],
        ),
      ],
    );

void main() {
  late SlideDocumentController doc;
  var next = 0;
  setUp(() {
    next = 0;
    doc = SlideDocumentController(deck(), newId: () => 'n${next++}');
  });

  ChartElement chart([String id = 'chart']) =>
      doc.presentation.slideById('s')!.findElement(id)! as ChartElement;

  /// Checks that [command] is one undo step that undo and redo replay.
  void oneStep(void Function() command) {
    final before = doc.presentation;
    final couldUndo = doc.canUndo;
    command();
    final after = doc.presentation;
    expect(after, isNot(before));
    expect(doc.undo(), isTrue);
    expect(doc.presentation, before);
    expect(doc.canUndo, couldUndo);
    expect(doc.redo(), isTrue);
    expect(doc.presentation, after);
  }

  group('insertChart', () {
    test('centers a sample chart of the kind on the slide, in front', () {
      late String id;
      oneStep(() => id = doc.insertChart('s', ChartKind.line));
      final c = chart(id);
      expect(c.kind, ChartKind.line);
      expect(c.data, SlideDocumentController.sampleChartData(ChartKind.line));
      expect(c.data.series, hasLength(3));
      expect(c.frame.width, SlideDocumentController.defaultChartWidth);
      expect(c.frame.height, SlideDocumentController.defaultChartHeight);
      expect(c.frame.x, (1920 - c.frame.width) / 2);
      expect(doc.presentation.slides.single.elements.last.id, id);
    });

    test('a pie starts with one series', () {
      final c = chart(doc.insertChart('s', ChartKind.pie));
      expect(c.data.series, hasLength(1));
    });

    test('fills a frame and draws data it is given', () {
      final data = ChartData(
        categories: const ['x'],
        series: [
          ChartSeries(values: const [1])
        ],
      );
      final frame = ElementFrame(x: 1, y: 2, width: 300, height: 200);
      final c =
          chart(doc.insertChart('s', ChartKind.area, frame: frame, data: data));
      expect(c.frame, frame);
      expect(c.data, data);
    });

    test('a narrow slide narrows the chart', () {
      doc = SlideDocumentController(
        Presentation(
          size: SlideSize.standard,
          slides: [Slide(id: 's')],
        ),
        newId: () => 'n${next++}',
      );
      expect(chart(doc.insertChart('s', ChartKind.bar)).frame.width,
          SlideSize.standard.width * 0.8);
    });
  });

  test('setChartData replaces the numbers', () {
    final data = ChartData.fromGrid([
      ['', 'A'],
      ['x', '5'],
    ]);
    oneStep(() => doc.setChartData('s', 'chart', data));
    expect(chart().data, data);
    expect(chart().options.title, 'Sales');
  });

  test('setChartData refuses data past the limits', () {
    final huge = ChartData(
      categories: List.filled(ChartData.maxCategories + 1, 'x'),
    );
    expect(() => doc.setChartData('s', 'chart', huge), throwsArgumentError);
    expect(doc.canUndo, isFalse);
  });

  test('setChartKind keeps the data', () {
    oneStep(() => doc.setChartKind('s', 'chart', ChartKind.horizontalBar));
    expect(chart().kind, ChartKind.horizontalBar);
    expect(chart().data, sampleChart().data);
  });

  test('setChartKind to the same kind records nothing', () {
    doc.setChartKind('s', 'chart', ChartKind.bar);
    expect(doc.canUndo, isFalse);
  });

  test('setChartOptions changes what it is given and keeps the rest', () {
    oneStep(() => doc.setChartOptions(
          's',
          'chart',
          showLegend: false,
          showGridlines: false,
          title: '',
        ));
    expect(
      chart().options,
      const ChartOptions(
        showLegend: false,
        showGridlines: false,
        showDataLabels: true,
        categoryAxisTitle: 'Quarter',
        valueAxisTitle: 'USD',
      ),
    );
    oneStep(() => doc.setChartOptions(
          's',
          'chart',
          showDataLabels: false,
          categoryAxisTitle: 'Q',
          valueAxisTitle: '',
        ));
    expect(chart().options.categoryAxisTitle, 'Q');
    expect(chart().options.showDataLabels, isFalse);
  });

  group('series', () {
    test('addChartSeries appends a named, zeroed series', () {
      oneStep(() => doc.addChartSeries('s', 'chart'));
      expect(chart().data.series.last.name, 'Series 3');
      expect(chart().data.series.last.values, [0, 0, 0]);
      oneStep(
          () => doc.addChartSeries('s', 'chart', name: 'Tax', values: [1, 2]));
      expect(chart().data.series.last.values, [1, 2, 0]);
    });

    test('addChartSeries refuses a series past the limits', () {
      doc.setChartData(
        's',
        'chart',
        ChartData(
          categories: const ['a'],
          series: [
            for (var i = 0; i < ChartData.maxSeries; i++) ChartSeries(),
          ],
        ),
      );
      expect(() => doc.addChartSeries('s', 'chart'), throwsArgumentError);
    });

    test('removeChartSeries drops it and its own color', () {
      doc.setChartColors('s', 'chart', const [
        SlideColor(0xFF000001),
        SlideColor(0xFF000002),
      ]);
      oneStep(() => doc.removeChartSeries('s', 'chart', 0));
      expect(chart().data.series.single.name, 'Costs');
      expect(chart().colors, const [SlideColor(0xFF000002)]);
      expect(chart().colorOf(0), const SlideColor(0xFF000002));
    });

    test('removing a series past the colors leaves them be', () {
      oneStep(() => doc.removeChartSeries('s', 'chart', 1));
      expect(chart().colors, const [SlideColor(0xFF224488)]);
    });

    test('the only series, or one out of range, cannot be removed', () {
      doc.removeChartSeries('s', 'chart', 1);
      expect(() => doc.removeChartSeries('s', 'chart', 0), throwsArgumentError);
      expect(() => doc.removeChartSeries('s', 'chart', 5), throwsRangeError);
    });
  });

  test('setChartColors sets the colors and an empty list clears them', () {
    oneStep(() => doc.setChartColors(
          's',
          'chart',
          const [SlideColor.theme(ThemeColor.accent5)],
        ));
    expect(chart().colorOf(0), const SlideColor.theme(ThemeColor.accent5));
    oneStep(() => doc.setChartColors('s', 'chart', const []));
    expect(chart().colorOf(0), ChartElement.defaultPalette.first);
  });

  test('chart commands refuse an element that is not a chart', () {
    expect(
        () => doc.setChartKind('s', 'box', ChartKind.pie), throwsArgumentError);
    expect(() => doc.addChartSeries('s', 'missing'), throwsArgumentError);
  });

  test('a chart in a group is edited in place', () {
    doc = SlideDocumentController(chartSamplePresentation());
    doc.setChartOptions('s2', 'pie', showDataLabels: true);
    final pie =
        doc.presentation.slideById('s2')!.findElement('pie')! as ChartElement;
    expect(pie.options.showDataLabels, isTrue);
  });

  test('resizing, moving and duplicating a chart work as for any element', () {
    doc.resizeElement('s', 'chart', width: 600, height: 300);
    expect(chart().frame.width, 600);
    doc.moveElements('s', {'chart'}, 10, 0);
    expect(chart().frame.x, 370);
    final copy = doc.duplicateElements('s', {'chart'}).single;
    expect(chart(copy).data, chart().data);
  });
}
