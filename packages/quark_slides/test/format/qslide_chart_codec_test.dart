import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/chart_sample.dart';
import '../support/sample_presentation.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Matcher throwsFormatAt(String path) => throwsA(
      isA<QslideFormatException>().having((e) => e.path, 'path', path),
    );

/// A one-slide deck at [version] holding [chart], a chart object.
Map<String, Object?> deckWith(Map<String, Object?> chart, {int version = 5}) =>
    {
      'schemaVersion': version,
      'slides': [
        {
          'id': 's',
          'elements': [chart],
        },
      ],
    };

Map<String, Object?> chartJson({
  Object? kind = 'bar',
  List<Object?> categories = const ['A', 'B'],
  List<Object?>? series,
  List<Object?>? colors,
}) =>
    {
      'id': 'c',
      'type': 'chart',
      'frame': {'x': 0, 'y': 0, 'width': 200, 'height': 100},
      'kind': kind,
      'categories': categories,
      'series': series ??
          [
            {
              'name': 'S',
              'values': [1, 2],
            },
          ],
      if (colors != null) 'colors': colors,
    };

ChartElement onlyChart(Presentation deck) =>
    deck.slides.single.elements.single as ChartElement;

void main() {
  group('golden chart_sample.qslide', () {
    test('encoding the chart deck matches the fixture byte for byte', () {
      expect(QslideCodec.encode(chartSamplePresentation()),
          fixture('chart_sample.qslide'));
    });

    test('decoding the fixture gives the chart deck', () {
      final deck = QslideCodec.decode(fixture('chart_sample.qslide'));
      expect(deck, chartSamplePresentation());
      final chart = deck.slides.first.elementById('chart')! as ChartElement;
      expect(chart.data.series[1].values, [8, 12.5, 20]);
      expect(chart.options.title, 'Sales');
      expect(chart.colorOf(0), const SlideColor(0xFF224488));
      expect(chart.colorOf(1), const SlideColor.theme(ThemeColor.accent2));
      final pie = deck.slides[1].findElement('pie')! as ChartElement;
      expect(pie.kind, ChartKind.pie);
      expect(pie.options.showLegend, isFalse);
    });

    test('every kind round-trips', () {
      for (final kind in ChartKind.values) {
        final chart = sampleChart().copyWith(kind: kind);
        final again = SlideElement.fromJson(
          jsonDecode(jsonEncode(chart.toJson())),
          r'$',
        );
        expect(again, chart, reason: kind.name);
      }
    });
  });

  group('forward compatibility', () {
    test('fields a newer writer added to a chart survive a round trip', () {
      final source = fixture('chart_future_fields.qslide');
      final again = QslideCodec.encode(QslideCodec.decode(source));
      expect(jsonDecode(again), jsonDecode(source));
    });

    test('a chart kind this version does not know is kept verbatim', () {
      final deck = QslideCodec.decode(fixture('chart_future_fields.qslide'));
      final scatter = deck.slides.single.elementById('c2');
      expect(scatter, isA<UnknownElement>());
      expect(scatter!.type, 'chart');
    });

    test('they survive edits to the chart too', () {
      final doc = SlideDocumentController(
        QslideCodec.decode(fixture('chart_future_fields.qslide')),
      );
      doc.setChartKind('s1', 'c1', ChartKind.area);
      doc.addChartSeries('s1', 'c1', name: 'Visitors');
      final chart =
          doc.presentation.slides.single.elementById('c1')! as ChartElement;
      doc.setChartData('s1', 'c1', chart.data.copyWith(categories: ['J', 'F']));
      final json = jsonDecode(QslideCodec.encode(doc.presentation)) as Map;
      final saved = (json['slides'] as List).single['elements'][0] as Map;
      expect(saved['kind'], 'area');
      expect(saved['categories'], ['J', 'F']);
      expect(saved['stacked'], 'percent');
      expect(saved['valueAxis'], {'min': 0, 'logBase': 10});
      expect((saved['series'] as List).first['marker'], 'diamond');
      expect((saved['series'] as List).last['name'], 'Visitors');
    });
  });

  group('reading', () {
    test('a short series is padded with zeros and a long one cut', () {
      final chart = onlyChart(QslideCodec.fromJson(deckWith(chartJson(
        categories: ['A', 'B', 'C'],
        series: [
          {
            'values': [1],
          },
          {
            'values': [1, 2, 3, 4],
          },
        ],
      ))));
      expect(chart.data.series[0].values, [1, 0, 0]);
      expect(chart.data.series[1].values, [1, 2, 3]);
    });

    test('a null value reads as 0 and a numeric category as text', () {
      final chart = onlyChart(QslideCodec.fromJson(deckWith(chartJson(
        categories: [2024, 'B'],
        series: [
          {
            'values': [null, 5],
          },
        ],
      ))));
      expect(chart.data.categories, ['2024', 'B']);
      expect(chart.data.series.single.values, [0, 5]);
    });

    test('options left out are the defaults', () {
      final chart = onlyChart(QslideCodec.fromJson(deckWith(chartJson())));
      expect(chart.options, const ChartOptions());
      expect(chart.colors, isEmpty);
    });

    test('a value that is not a number is refused at its path', () {
      expect(
        () => QslideCodec.fromJson(deckWith(chartJson(series: [
          {
            'values': [1, 'x'],
          },
        ]))),
        throwsFormatAt(r'$.slides[0].elements[0].series[0].values[1]'),
      );
    });

    test('a bad color is refused at its path', () {
      expect(
        () => QslideCodec.fromJson(deckWith(chartJson(colors: ['red']))),
        throwsFormatAt(r'$.slides[0].elements[0].colors[0]'),
      );
    });

    test('a chart past the limits is refused', () {
      expect(
        () => QslideCodec.fromJson(deckWith(chartJson(
          categories: List.filled(ChartData.maxCategories + 1, 'x'),
        ))),
        throwsFormatAt(r'$.slides[0].elements[0]'),
      );
      expect(
        () => QslideCodec.fromJson(deckWith(chartJson(
          categories: List.filled(200, 'x'),
          series: List.filled(30, {'values': <int>[]}),
        ))),
        throwsFormatAt(r'$.slides[0].elements[0]'),
      );
    });
  });

  group('migration', () {
    test('this version writes schema 5', () {
      expect(QslideCodec.schemaVersion, 5);
    });

    test('the golden v4 file reads as the sample deck', () {
      final json = jsonDecode(fixture('v4_sample.qslide')) as Map;
      expect(json['schemaVersion'], 4);
      expect(QslideCodec.decode(fixture('v4_sample.qslide')),
          samplePresentation());
    });

    test('it saves as version 5 and otherwise byte for byte as before', () {
      final saved =
          QslideCodec.encode(QslideCodec.decode(fixture('v4_sample.qslide')));
      expect(saved, fixture('sample.qslide'));
      expect(
        saved,
        fixture('v4_sample.qslide').replaceFirst(
          '"schemaVersion": 4',
          '"schemaVersion": 5',
        ),
      );
    });

    test('every older version migrates to 5', () {
      for (final name in [
        'v1_sample.qslide',
        'v2_sample.qslide',
        'v3_sample.qslide',
        'v4_sample.qslide',
      ]) {
        final json = QslideCodec.toJson(QslideCodec.decode(fixture(name)));
        expect(json['schemaVersion'], 5, reason: name);
      }
    });

    test('a chart a version 4 file carried reads as a chart', () {
      final deck = QslideCodec.fromJson(deckWith(chartJson(), version: 4));
      expect(onlyChart(deck).data.series.single.values, [1, 2]);
    });

    test('a newer schema is refused', () {
      expect(
        () => QslideCodec.decode(fixture('newer_schema.qslide')),
        throwsFormatAt(r'$.schemaVersion'),
      );
    });
  });
}
