import 'package:flutter/material.dart';
import 'package:quark_slides/quark_slides.dart';

/// A small live picture of a [kind] chart: the package's
/// [SlideChartPainter] drawing `SlideDocumentController.sampleChartData`
/// in [theme] — the deck's, or [SlideThemes.light] for a deck with none —
/// with no title or legend, so the picker's previews look like the chart
/// that goes in.
///
/// It is decoration: the tile around it carries the label, so it is left
/// out of the semantics tree.
class SlideChartKindPreview extends StatelessWidget {
  /// A preview of a [kind] chart in [theme], [size] across.
  const SlideChartKindPreview({
    required this.kind,
    this.theme,
    this.size = const Size(96, 64),
    super.key,
  });

  /// What kind of chart it draws.
  final ChartKind kind;

  /// The theme its colors resolve against; null for the light one.
  final SlideTheme? theme;

  /// How big it is drawn.
  final Size size;

  @override
  Widget build(BuildContext context) {
    final chart = ChartElement(
      id: 'preview',
      frame: ElementFrame(x: 0, y: 0, width: size.width, height: size.height),
      kind: kind,
      data: SlideDocumentController.sampleChartData(kind),
      options: const ChartOptions(showLegend: false, showGridlines: false),
    );
    return ExcludeSemantics(
      child: CustomPaint(
        size: size,
        painter: SlideChartPainter(chart, theme ?? SlideThemes.light),
      ),
    );
  }
}
