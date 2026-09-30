import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// The rounded label a `PhotoGridScrollLabel` floats over the grid while it
/// scrolls, such as "March 2025".
///
/// Key prefix: `photo_grid_scroll_label` on the pill.
///
/// ```dart
/// PhotoGridScrollLabelPill(label: 'March 2025');
/// ```
class PhotoGridScrollLabelPill extends StatelessWidget {
  /// Creates the pill reading [label].
  const PhotoGridScrollLabelPill({required this.label, super.key});

  /// The pill's text.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return DecoratedBox(
      key: const ValueKey('photo_grid_scroll_label'),
      decoration: ShapeDecoration(
        color: tokens.card.withValues(alpha: 0.9),
        shape: StadiumBorder(side: BorderSide(color: tokens.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingMd,
          vertical: tokens.spacingSm,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.primary,
          ),
        ),
      ),
    );
  }
}
