import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// The header over one `PhotoGridSection`, pinned to the top of the viewport
/// by its `PhotoGrid` while the section scrolls past.
///
/// Opaque, in the page's background color, so the photos sliding under it
/// never show through. Styled like the sidebar's "Albums" header: small,
/// semi-bold, muted.
///
/// Key prefix: `photo_grid_section_<id>`, set by the grid.
///
/// ```dart
/// PhotoGridSectionHeader(label: 'March 2025');
/// ```
class PhotoGridSectionHeader extends StatelessWidget {
  /// Creates a header reading [label].
  const PhotoGridSectionHeader({required this.label, super.key});

  /// The header text.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return ColoredBox(
      color: tokens.background,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingSm + tokens.spacingXs,
          vertical: tokens.spacingSm,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: tokens.mutedForeground,
          ),
        ),
      ),
    );
  }
}
