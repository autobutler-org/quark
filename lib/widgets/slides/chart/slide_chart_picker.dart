import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/chart/slide_chart_kind_tile.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Insert > Chart (#1160): the five kinds of chart as
/// [SlideChartKindTile]s, each a small live preview of the sample data a
/// new chart holds, starting at [kind].
///
/// A tile picks the kind. "Draw" calls [onDraw] to arm the chart tool, so
/// a click on the slide places the chart and a drag sizes it; "Insert"
/// calls [onInsert] to put it in the middle of the slide, which is the way
/// in from the keyboard. Either closes the menu the picker is in.
///
/// The tiles wrap, so the picker fits a phone's sheet and a 2.0 text
/// scale.
///
/// Key prefixes: `slide_chart_picker` on the picker, the tiles'
/// `slide_chart_pick_<kind>`, and `slide_chart_draw` and
/// `slide_chart_insert` on the buttons.
class SlideChartPicker extends StatefulWidget {
  /// A picker starting at [kind].
  const SlideChartPicker({
    required this.onDraw,
    required this.onInsert,
    this.kind = ChartKind.bar,
    this.theme,
    super.key,
  });

  /// Arms the chart tool with the kind picked.
  final ValueChanged<ChartKind> onDraw;

  /// Puts a chart of the kind picked in the middle of the slide.
  final ValueChanged<ChartKind> onInsert;

  /// The kind it starts at.
  final ChartKind kind;

  /// The deck's theme, which the previews are drawn in.
  final SlideTheme? theme;

  @override
  State<SlideChartPicker> createState() => _SlideChartPickerState();
}

class _SlideChartPickerState extends State<SlideChartPicker> {
  late ChartKind _kind = widget.kind;

  void _done(ValueChanged<ChartKind> action) {
    MenuController.maybeOf(context)?.close();
    action(_kind);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final name = chartKindName(_kind).toLowerCase();
    return Padding(
      key: const ValueKey('slide_chart_picker'),
      padding: EdgeInsets.all(tokens.spacingMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 3 * 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: tokens.spacingSm,
          children: [
            Wrap(
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingSm,
              children: [
                for (final kind in ChartKind.values)
                  SlideChartKindTile(
                    kind: kind,
                    theme: widget.theme,
                    selected: kind == _kind,
                    onTap: () => setState(() => _kind = kind),
                  ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingSm,
              children: [
                QuarkBarChip(
                  key: const ValueKey('slide_chart_draw'),
                  icon: QuarkIcons.select_tool,
                  label: 'Draw',
                  tooltip: 'Draw a $name on the slide',
                  keepLabel: true,
                  onPressed: () => _done(widget.onDraw),
                ),
                QuarkBarChip(
                  key: const ValueKey('slide_chart_insert'),
                  icon: QuarkIcons.insert_chart,
                  label: 'Insert',
                  tooltip: 'Insert a $name in the middle of the slide',
                  keepLabel: true,
                  onPressed: () => _done(widget.onInsert),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
