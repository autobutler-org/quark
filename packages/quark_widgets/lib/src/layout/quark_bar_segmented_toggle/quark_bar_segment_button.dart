import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';
import '../quark_bar_icon_button.dart';
import '../quark_bar_segmented_toggle.dart';

/// One segment of a [QuarkBarSegmentedToggle]: a glyph and a word, tinted
/// with the primary color while [selected].
///
/// It draws [QuarkBarIconButton.size] tall with no border of its own, since
/// the toggle draws one frame around every segment, and answers taps across
/// [QuarkBarIconButton.hitSize]. The toggle rounds the outer corners of its
/// first and last segments through [borderRadius].
///
/// Key prefixes: `bar_segment_<id>` on the label.
///
/// ```dart
/// QuarkBarSegmentButton(
///   segment: segment,
///   selected: segment.id == selectedId,
///   borderRadius: BorderRadius.zero,
///   onSelected: onSelected,
/// );
/// ```
class QuarkBarSegmentButton extends StatelessWidget {
  /// Creates the button for [segment].
  const QuarkBarSegmentButton({
    required this.segment,
    required this.selected,
    required this.borderRadius,
    required this.onSelected,
    super.key,
  });

  /// The choice this button offers.
  final QuarkBarSegment segment;

  /// Whether [segment] is the one on. A selected segment ignores taps.
  final bool selected;

  /// The corners of the tint and the ink, so the first and last segments
  /// follow the toggle's rounded frame.
  final BorderRadius borderRadius;

  /// Called with [segment]'s id when the user picks it while it is off.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final foreground = selected ? tokens.primary : tokens.secondaryForeground;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: Tooltip(
        message: segment.label,
        child: TextButton.icon(
          onPressed: selected ? () {} : () => onSelected(segment.id),
          icon: Icon(segment.icon),
          label: Text(
            segment.label,
            key: ValueKey('bar_segment_${segment.id}'),
          ),
          style: TextButton.styleFrom(
            foregroundColor: foreground,
            iconColor: foreground,
            backgroundColor: selected
                ? tokens.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            iconSize: QuarkBarIconButton.glyphSize,
            textStyle: Theme.of(context).textTheme.labelLarge,
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacingSm + tokens.spacingXs,
            ),
            minimumSize: const Size(0, QuarkBarIconButton.size),
            maximumSize: const Size(double.infinity, QuarkBarIconButton.size),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
          ),
        ),
      ),
    );
  }
}
