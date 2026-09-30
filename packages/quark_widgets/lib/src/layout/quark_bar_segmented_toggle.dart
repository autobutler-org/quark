import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'quark_bar_icon_button.dart';
import 'quark_bar_segmented_toggle/quark_bar_segment_button.dart';

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
/// The selected segment is inert: choosing what is already on is not a change
/// worth a callback.
///
/// The frame is drawn at [QuarkBarIconButton.size], but each segment answers
/// taps across [QuarkBarIconButton.hitSize], the same as every other bar
/// button (#2605), and grows taller when a large text size needs the room
/// (#2606). Material's `SegmentedButton` cannot do that, which is why the
/// segments are built here.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, segment) in segments.indexed)
          // Each segment draws its own border; shifting every one after the
          // first a pixel left lays each seam over its neighbor's edge, so
          // the frame reads as one box with single-pixel dividers.
          Transform.translate(
            offset: Offset(-i.toDouble(), 0),
            child: QuarkBarSegmentButton(
              segment: segment,
              selected: segment.id == selectedId,
              borderRadius: BorderRadius.horizontal(
                left: i == 0 ? radius : Radius.zero,
                right: i == segments.length - 1 ? radius : Radius.zero,
              ),
              onSelected: onSelected,
            ),
          ),
      ],
    );
  }
}
