import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/chart/slide_chart_kind_preview.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One kind in the chart picker: a [SlideChartKindPreview] over the kind's
/// name, outlined in the primary color while [selected]. A tap calls
/// [onTap]; a screen reader hears "Bar chart", a button, selected or not.
///
/// The tile is at least 48 by 48 and its name wraps, so it survives a 2.0
/// text scale.
///
/// Key prefixes: `slide_chart_pick_<kind>` on the tile.
class SlideChartKindTile extends StatelessWidget {
  /// The tile for [kind].
  const SlideChartKindTile({
    required this.kind,
    required this.selected,
    required this.onTap,
    this.theme,
    super.key,
  });

  /// The kind it offers.
  final ChartKind kind;

  /// Whether it is the kind picked.
  final bool selected;

  /// Picks the kind.
  final VoidCallback onTap;

  /// The deck's theme, which the preview is drawn in.
  final SlideTheme? theme;

  /// The tile's width.
  static const double width = 112;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final name = chartKindName(kind);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Material(
        color: selected ? tokens.primary.withValues(alpha: 0.08) : tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(
            color: selected ? tokens.primary : tokens.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('slide_chart_pick_${kind.name}'),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: SizedBox(
              width: width,
              child: Padding(
                padding: EdgeInsets.all(tokens.spacingSm),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: tokens.spacingXs,
                    children: [
                      SlideChartKindPreview(kind: kind, theme: theme),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: tokens.foreground),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
