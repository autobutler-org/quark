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
    return SegmentedButton<String>(
      segments: [
        for (final segment in segments)
          ButtonSegment(
            value: segment.id,
            icon: Icon(segment.icon),
            tooltip: segment.label,
            label: Text(
              segment.label,
              key: ValueKey('bar_segment_${segment.id}'),
            ),
          ),
      ],
      selected: {selectedId},
      onSelectionChanged: (selection) => onSelected(selection.single),
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        foregroundColor: tokens.secondaryForeground,
        backgroundColor: tokens.input,
        selectedForegroundColor: tokens.primary,
        selectedBackgroundColor: tokens.primary.withValues(alpha: 0.12),
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
        ),
        iconSize: QuarkBarIconButton.glyphSize,
        textStyle: Theme.of(context).textTheme.labelLarge,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingSm + tokens.spacingXs,
        ),
        minimumSize: const Size(0, QuarkBarIconButton.size),
        maximumSize: const Size(double.infinity, QuarkBarIconButton.size),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // SegmentedButton floors its height at 40 and only density moves the
        // floor: one step down is 36, a bar button's height.
        visualDensity: const VisualDensity(vertical: -1),
      ),
    );
  }
}
