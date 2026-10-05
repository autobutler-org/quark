import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../chart/chart_axis_scale.dart';
import '../chart/chart_geometry.dart';
import '../chart/chart_layout.dart';
import '../chart/chart_pie_slice.dart';
import '../model/chart_data.dart';
import '../model/chart_kind.dart';
import '../model/slide_element.dart';
import '../model/text_paragraph.dart';
import '../model/text_run.dart';
import '../theme/slide_theme.dart';
import '../theme/theme_color.dart';
import 'slide_text_layout.dart';

/// Paints a [ChartElement] into the box it is given — the chart's frame, in
/// slide units: its title, legend, axes, gridlines, tick labels, axis
/// titles, the bars, lines, areas or pie, and its value labels.
///
/// Colors resolve against [theme] as it paints, so a theme change repaints
/// the chart: series in [ChartElement.colorOf], text in the theme's text
/// color, axes and tick labels in its secondary text color, gridlines in
/// that color faded. Text is set through [SlideTextLayout] in the theme's
/// body font, at sizes from [ChartLayout.titleFontSize] and
/// [ChartLayout.labelFontSize]. Where the parts go is [ChartLayout]'s
/// arithmetic, and the plot's is [chartBars], [chartLinePoints] and
/// [ChartPieSlice.of]; axis labels that would overlap are thinned with
/// [chartVisibleLabels] and value labels dropped with [chartPlaceLabels].
class SlideChartPainter extends CustomPainter {
  /// Creates a painter for [chart] in [theme].
  const SlideChartPainter(this.chart, this.theme);

  /// The chart to paint.
  final ChartElement chart;

  /// The theme its role colors and text resolve against.
  final SlideTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final painter = _ChartPaint(chart, theme, canvas, size);
    painter.paint();
    painter.dispose();
  }

  @override
  bool shouldRepaint(SlideChartPainter oldDelegate) =>
      oldDelegate.chart != chart || oldDelegate.theme != theme;
}

/// One paint of one chart: the text it measured, disposed when done.
class _ChartPaint {
  _ChartPaint(this.chart, this.theme, this.canvas, this.size)
      : labelSize = ChartLayout.labelFontSize(size),
        titleSize = ChartLayout.titleFontSize(size);

  final ChartElement chart;
  final SlideTheme theme;
  final Canvas canvas;
  final Size size;
  final double labelSize;
  final double titleSize;
  final List<TextPainter> _texts = [];

  Color _role(ThemeColor role) => Color(theme.colors[role]);

  Color get _textColor => _role(ThemeColor.text);

  Color get _mutedColor => _role(ThemeColor.text2);

  /// [text] laid out at [fontSize] in [color], no wider than [maxWidth].
  TextPainter _text(
    String text, {
    required double fontSize,
    Color? color,
    bool bold = false,
    double maxWidth = double.infinity,
  }) {
    final layout = SlideTextLayout(
      fontSize: fontSize,
      textColor: color ?? _textColor,
      fontFamily: theme.fontOf(theme.body),
      theme: theme,
    );
    final painter = TextPainter(
      text: layout.paragraphSpan(
        TextParagraph(
          [TextRun(text, bold: bold)],
          alignment: TextAlignment.center,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
    _texts.add(painter);
    return painter;
  }

  void dispose() {
    for (final t in _texts) {
      t.dispose();
    }
  }

  /// The values drawn, `[series][category]`.
  List<List<double>> get _values => [
        for (final s in chart.data.series) s.values,
      ];

  void paint() {
    final options = chart.options;
    final data = chart.data;
    final kind = chart.kind;
    final horizontal = kind == ChartKind.horizontalBar;
    final title = options.title.trim().isEmpty
        ? null
        : _text(
            options.title.trim(),
            fontSize: titleSize,
            bold: true,
            maxWidth: size.width * 0.9,
          );
    final legend = options.showLegend ? _legend() : null;

    ChartAxisScale? scale;
    var valueLabels = <(double, TextPainter)>[];
    var categoryLabels = <TextPainter>[];
    TextPainter? valueTitle;
    TextPainter? categoryTitle;
    if (kind.hasAxes) {
      final range = data.range;
      scale = ChartAxisScale.nice(
        math.min(0, range?.min ?? 0),
        math.max(0, range?.max ?? 0),
      );
      valueLabels = [
        for (final tick in scale.ticks)
          (
            tick,
            _text(scale.label(tick), fontSize: labelSize, color: _mutedColor),
          ),
      ];
      final categoryWidth = horizontal
          ? size.width * 0.3
          : math.max(
              labelSize * 3, size.width / math.max(1, data.categories.length));
      categoryLabels = [
        for (final c in data.categories)
          _text(c,
              fontSize: labelSize, color: _mutedColor, maxWidth: categoryWidth),
      ];
      if (options.valueAxisTitle.trim().isNotEmpty) {
        valueTitle = _text(options.valueAxisTitle.trim(),
            fontSize: labelSize, maxWidth: size.height * 0.8);
      }
      if (options.categoryAxisTitle.trim().isNotEmpty) {
        categoryTitle = _text(options.categoryAxisTitle.trim(),
            fontSize: labelSize, maxWidth: size.height * 0.8);
      }
    }
    Size largest(Iterable<TextPainter> texts) => texts.isEmpty
        ? Size.zero
        : Size(
            texts.map((t) => t.width).reduce(math.max),
            texts.map((t) => t.height).reduce(math.max),
          );

    final layout = ChartLayout.of(
      size: size,
      title: title?.size ?? Size.zero,
      legend: legend?.size ?? Size.zero,
      valueAxisTitle: valueTitle?.size ?? Size.zero,
      categoryAxisTitle: categoryTitle?.size ?? Size.zero,
      valueLabels: largest(valueLabels.map((l) => l.$2)),
      categoryLabels: largest(categoryLabels),
      horizontal: horizontal,
      hasAxes: kind.hasAxes,
    );
    if (title != null) title.paint(canvas, layout.title.topLeft);
    legend?.paint(layout.legend.topLeft);
    final plot = layout.plot;
    if (plot.isEmpty) return;
    if (scale == null) return _pie(plot);
    _axes(plot, scale, valueLabels, categoryLabels, horizontal);
    if (valueTitle != null) {
      _axisTitle(valueTitle, layout.valueAxisTitle, turned: !horizontal);
    }
    if (categoryTitle != null) {
      _axisTitle(categoryTitle, layout.categoryAxisTitle, turned: horizontal);
    }
    if (data.series.isEmpty || data.categories.isEmpty) return;
    switch (kind) {
      case ChartKind.bar || ChartKind.horizontalBar:
        _bars(plot, scale, horizontal);
      case ChartKind.line || ChartKind.area:
        _lines(plot, scale, filled: kind == ChartKind.area);
      case ChartKind.pie:
        break;
    }
  }

  /// Measures the legend; its `paint` draws it with its top-left at a
  /// point.
  ({Size size, void Function(Offset) paint})? _legend() {
    final entries = chart.legendEntries;
    if (entries.isEmpty) return null;
    final swatch = labelSize * 0.8;
    final texts = [
      for (final e in entries)
        _text(e.name, fontSize: labelSize, maxWidth: size.width * 0.4),
    ];
    final items = [
      for (final t in texts)
        Size(swatch + labelSize * 0.4 + t.width, math.max(swatch, t.height)),
    ];
    final flow = chartFlow(
      items,
      size.width * 0.9,
      gap: labelSize,
      rowGap: labelSize * 0.3,
    );
    return (
      size: flow.size,
      paint: (Offset at) {
        for (final (i, e) in entries.indexed) {
          final origin = at + flow.offsets[i];
          final height = items[i].height;
          canvas.drawRect(
            Rect.fromLTWH(
                origin.dx, origin.dy + (height - swatch) / 2, swatch, swatch),
            Paint()..color = Color(e.color.resolve(theme)),
          );
          texts[i].paint(
            canvas,
            origin +
                Offset(
                    swatch + labelSize * 0.4, (height - texts[i].height) / 2),
          );
        }
      },
    );
  }

  void _axes(
    Rect plot,
    ChartAxisScale scale,
    List<(double, TextPainter)> valueLabels,
    List<TextPainter> categoryLabels,
    bool horizontal,
  ) {
    final grid = Paint()
      ..color = _mutedColor.withValues(alpha: 0.25)
      ..strokeWidth = math.max(1, labelSize / 16);
    final axis = Paint()
      ..color = _mutedColor
      ..strokeWidth = math.max(1, labelSize / 10);
    final gap = labelSize * 0.4;
    for (final (tick, label) in valueLabels) {
      final f = scale.fraction(tick);
      if (horizontal) {
        final x = plot.left + f * plot.width;
        if (chart.options.showGridlines) {
          canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
        }
        label.paint(canvas, Offset(x - label.width / 2, plot.bottom + gap));
      } else {
        final y = plot.bottom - f * plot.height;
        if (chart.options.showGridlines) {
          canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        }
        label.paint(
          canvas,
          Offset(plot.left - gap - label.width, y - label.height / 2),
        );
      }
    }
    final count = categoryLabels.length;
    final centers = [
      for (var c = 0; c < count; c++)
        horizontal
            ? chartCategoryCenter(c, count, plot.top, plot.height)
            : chartCategoryCenter(c, count, plot.left, plot.width),
    ];
    final shown = chartVisibleLabels(
      centers,
      [
        for (final l in categoryLabels) horizontal ? l.height : l.width,
      ],
      gap: labelSize * 0.3,
    );
    for (final c in shown) {
      final label = categoryLabels[c];
      label.paint(
        canvas,
        horizontal
            ? Offset(
                plot.left - gap - label.width, centers[c] - label.height / 2)
            : Offset(centers[c] - label.width / 2, plot.bottom + gap),
      );
    }
    // The axis lines: along the baseline, and down the side.
    if (horizontal) {
      final x = plot.left + scale.fraction(scale.baseline) * plot.width;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), axis);
    } else {
      final y = chartBaselineY(plot, scale);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), axis);
    }
  }

  void _axisTitle(TextPainter text, Rect at, {required bool turned}) {
    if (!turned) return text.paint(canvas, at.topLeft);
    canvas.save();
    canvas.translate(at.center.dx, at.center.dy);
    canvas.rotate(-math.pi / 2);
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
  }

  void _bars(Rect plot, ChartAxisScale scale, bool horizontal) {
    final bars = chartBars(
      values: _values,
      plot: plot,
      scale: scale,
      horizontal: horizontal,
    );
    final labels = <(Rect, TextPainter)>[];
    for (final (s, row) in bars.indexed) {
      final paint = Paint()..color = Color(chart.colorOf(s).resolve(theme));
      for (final (c, bar) in row.indexed) {
        canvas.drawRect(bar, paint);
        if (!chart.options.showDataLabels) continue;
        final value = _values[s][c];
        final text = _text(formatChartValue(value), fontSize: labelSize);
        final gap = labelSize * 0.2;
        final negative = value < 0;
        final origin = horizontal
            ? Offset(
                negative ? bar.left - gap - text.width : bar.right + gap,
                bar.center.dy - text.height / 2,
              )
            : Offset(
                bar.center.dx - text.width / 2,
                negative ? bar.bottom + gap : bar.top - gap - text.height,
              );
        labels.add((origin & text.size, text));
      }
    }
    _dataLabels(labels, Offset.zero & size);
  }

  void _lines(Rect plot, ChartAxisScale scale, {required bool filled}) {
    final width = math.max(2.0, labelSize * 0.15);
    final baseline = chartBaselineY(plot, scale);
    final labels = <(Rect, TextPainter)>[];
    for (final (s, values) in _values.indexed) {
      final color = Color(chart.colorOf(s).resolve(theme));
      final points = chartLinePoints(values, plot, scale);
      final line = Path()..addPolygon(points, false);
      if (filled && points.isNotEmpty) {
        final area = Path()
          ..moveTo(points.first.dx, baseline)
          ..addPolygon(points, false)
          ..lineTo(points.last.dx, baseline)
          ..close();
        canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.45));
      }
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
      if (!filled) {
        for (final p in points) {
          canvas.drawCircle(p, width * 1.5, Paint()..color = color);
        }
      }
      if (!chart.options.showDataLabels) continue;
      for (final (c, p) in points.indexed) {
        final text = _text(formatChartValue(values[c]), fontSize: labelSize);
        final origin = p - Offset(text.width / 2, text.height + width * 2);
        labels.add((origin & text.size, text));
      }
    }
    _dataLabels(labels, Offset.zero & size);
  }

  void _pie(Rect plot) {
    final series = chart.data.series;
    if (series.isEmpty) return;
    final slices = ChartPieSlice.of(series.first.values);
    final radius = math.min(plot.width, plot.height) / 2;
    final circle = Rect.fromCircle(center: plot.center, radius: radius);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, radius / 100)
      ..color = _role(ThemeColor.background);
    for (final slice in slices) {
      canvas.drawArc(
        circle,
        slice.startAngle,
        slice.sweepAngle,
        true,
        Paint()..color = Color(chart.colorOf(slice.index).resolve(theme)),
      );
    }
    if (slices.length > 1) {
      for (final slice in slices) {
        canvas.drawArc(circle, slice.startAngle, slice.sweepAngle, true, edge);
      }
    }
    if (!chart.options.showDataLabels) return;
    final background = _role(ThemeColor.background);
    _dataLabels([
      for (final slice in slices)
        () {
          final text = _text(
            formatChartValue(slice.value),
            fontSize: labelSize,
            color: background,
            bold: true,
          );
          final at =
              plot.center + Offset.fromDirection(slice.midAngle, radius * 0.65);
          return (
            Rect.fromCenter(center: at, width: text.width, height: text.height),
            text,
          );
        }(),
    ], Offset.zero & size);
  }

  /// Paints the value labels that fit, in order: see [chartPlaceLabels].
  void _dataLabels(List<(Rect, TextPainter)> labels, Rect bounds) {
    final kept = chartPlaceLabels([for (final l in labels) l.$1], bounds);
    for (final (i, (rect, text)) in labels.indexed) {
      if (kept[i]) text.paint(canvas, rect.topLeft);
    }
  }
}
