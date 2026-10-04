import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'quark_bar_icon_button.dart';

/// One choice in a [QuarkBarSegmentedToggle].
@immutable
class QuarkBarSegment {
  /// Creates a segment called [label], identified by [id].
  const QuarkBarSegment({
    required this.id,
    required this.icon,
    required this.label,
  });

  /// Identifies the segment in [QuarkBarSegmentedToggle.onSelected] and in
  /// its key, `bar_segment_<id>`.
  final String id;

  /// The glyph, from `QuarkIcons`.
  final IconData icon;

  /// The word beside the glyph, which is also its tooltip.
  final String label;
}

/// A joined row of mutually exclusive choices, in the top bar's bordered,
/// filled style and at its height — the list/grid switch in Files.
///
/// Each segment answers taps across a [QuarkBarIconButton.tapTargetSize]
/// height around its [QuarkBarIconButton.size] visual, and the toggle keeps
/// [QuarkBarIconButton.tapTargetMargin] of space either side, like every bar
/// control (#2605). Screen readers hear each segment as selectable, with the
/// one that is on announced as selected.
///
/// The selected segment is inert: choosing what is already on is not a change
/// worth a callback.
///
/// Key prefixes: `bar_segment_<id>` on each segment's label, one per entry in
/// [segments].
///
/// ```dart
/// QuarkBarSegmentedToggle(
///   segments: const [
///     QuarkBarSegment(id: 'list', icon: QuarkIcons.view_list_rounded, label: 'List'),
///     QuarkBarSegment(id: 'grid', icon: QuarkIcons.grid_view_rounded, label: 'Grid'),
///   ],
///   selectedId: isGrid ? 'grid' : 'list',
///   onSelected: (id) => setGrid(id == 'grid'),
/// );
/// ```
class QuarkBarSegmentedToggle extends StatelessWidget {
  /// Creates a toggle offering [segments], with [selectedId] on.
  const QuarkBarSegmentedToggle({
    required this.segments,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  /// The choices, in order.
  final List<QuarkBarSegment> segments;

  /// The [QuarkBarSegment.id] currently on.
  final String selectedId;

  /// Called with the id of the segment the user chose. Never called with
  /// [selectedId].
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final radius = Radius.circular(tokens.radiusLg);
    final textStyle = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: QuarkBarIconButton.tapTargetMargin,
      ),
      // The border is drawn around the visual only, inset from the touch
      // target above and below it. Material's SegmentedButton cannot do this:
      // its touch target is 48dp less its density, and the density that
      // brings it down to a bar button's 36 leaves a 44dp target (#2605).
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: QuarkBarIconButton.tapTargetMargin,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.input,
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.all(radius),
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, segment) in segments.indexed) ...[
                if (index > 0)
                  Container(
                    width: 1,
                    height: QuarkBarIconButton.size,
                    color: tokens.border,
                  ),
                MergeSemantics(
                  child: Semantics(
                    inMutuallyExclusiveGroup: true,
                    selected: segment.id == selectedId,
                    child: Tooltip(
                      message: segment.label,
                      child: TextButton.icon(
                        onPressed: () {
                          if (segment.id != selectedId) onSelected(segment.id);
                        },
                        icon: Icon(segment.icon),
                        label: Text(
                          segment.label,
                          key: ValueKey('bar_segment_${segment.id}'),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: segment.id == selectedId
                              ? tokens.primary
                              : tokens.secondaryForeground,
                          iconColor: segment.id == selectedId
                              ? tokens.primary
                              : tokens.secondaryForeground,
                          backgroundColor: segment.id == selectedId
                              ? tokens.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.horizontal(
                              left: index == 0 ? radius : Radius.zero,
                              right: index == segments.length - 1
                                  ? radius
                                  : Radius.zero,
                            ),
                          ),
                          iconSize: QuarkBarIconButton.glyphSize,
                          textStyle: textStyle,
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.spacingSm + tokens.spacingXs,
                          ),
                          minimumSize: const Size(0, QuarkBarIconButton.size),
                          maximumSize: const Size(
                            double.infinity,
                            QuarkBarIconButton.size,
                          ),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          visualDensity: VisualDensity.standard,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
