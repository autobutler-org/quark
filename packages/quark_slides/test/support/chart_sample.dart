import 'package:quark_slides/quark_slides.dart';

/// A bar chart `chart` at (360, 200), 1200 × 700 units: three quarters by
/// two series, a literal color for the first series, a title, value
/// labels and both axis titles.
ChartElement sampleChart() => ChartElement(
      id: 'chart',
      frame: ElementFrame(x: 360, y: 200, width: 1200, height: 700),
      kind: ChartKind.bar,
      data: ChartData(
        categories: const ['Q1', 'Q2', 'Q3'],
        series: [
          ChartSeries(name: 'Revenue', values: const [12, 30, 42]),
          ChartSeries(name: 'Costs', values: const [8, 12.5, 20]),
        ],
      ),
      options: const ChartOptions(
        title: 'Sales',
        showDataLabels: true,
        categoryAxisTitle: 'Quarter',
        valueAxisTitle: 'USD',
      ),
      colors: const [SlideColor(0xFF224488)],
    );

/// A deck with [sampleChart] on slide `s1` and a pie `pie` grouped with a
/// shape on slide `s2`. `test/fixtures/chart_sample.qslide` is its golden
/// encoding.
Presentation chartSamplePresentation() => Presentation(
      title: 'Charts',
      slides: [
        Slide(id: 's1', elements: [sampleChart()]),
        Slide(
          id: 's2',
          elements: [
            GroupElement(
              id: 'g',
              frame: ElementFrame(x: 0, y: 0, width: 400, height: 500),
              children: [
                ChartElement(
                  id: 'pie',
                  frame: ElementFrame(x: 0, y: 0, width: 400, height: 400),
                  kind: ChartKind.pie,
                  data: ChartData(
                    categories: const ['North', 'South'],
                    series: [
                      ChartSeries(values: const [3, 1])
                    ],
                  ),
                  options: const ChartOptions(
                    showLegend: false,
                    showGridlines: false,
                  ),
                ),
                ShapeElement(
                  id: 'sh',
                  frame: ElementFrame(x: 0, y: 400, width: 400, height: 100),
                ),
              ],
            ),
          ],
        ),
      ],
    );
