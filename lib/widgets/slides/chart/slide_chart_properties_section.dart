import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/chart/slide_chart_title_field.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The properties panel's chart section (#1160): what kind of chart the
/// selected one is and how much data it holds, and its title. A null
/// [onTitleChanged] — a view-only presentation — shows the title in a
/// field that takes no input.
///
/// Position and size are the panel's ordinary fields above it.
///
/// Key prefixes: `slide_prop_chart_kind` on the readout,
/// `slide_prop_chart_title` on the title field.
class SlideChartPropertiesSection extends StatelessWidget {
  /// The section for [chart].
  const SlideChartPropertiesSection({
    required this.chart,
    this.onTitleChanged,
    super.key,
  });

  /// The selected chart.
  final ChartElement chart;

  /// Saves a new title; null takes no input.
  final ValueChanged<String>? onTitleChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final data = chart.data;
    return QuarkSection(
      title: 'Chart',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: tokens.spacingSm,
        children: [
          Text(
            '${chartKindName(chart.kind)}, '
            '${count(data.series.length, 'series', 'series')} × '
            '${count(data.categories.length, 'category', 'categories')}',
            key: const ValueKey('slide_prop_chart_kind'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.foreground),
          ),
          SlideChartTitleField(
            fieldKey: 'slide_prop_chart_title',
            value: chart.options.title,
            onSubmitted: onTitleChanged,
          ),
        ],
      ),
    );
  }
}
