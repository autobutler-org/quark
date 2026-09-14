import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// The "All photos" row that leads an `AlbumSidebar`'s album list.
///
/// Drawn like a root `AlbumTreeTile`, with a blank where the chevron would be
/// so the glyphs line up, but it is not an album: no count, no long press, no
/// children.
///
/// Key prefix: `album_sidebar_all_photos` on the row.
///
/// ```dart
/// AlbumSidebarAllPhotosTile(
///   isSelected: controller.selectedAlbumId == null,
///   onTap: controller.showAllPhotos,
/// );
/// ```
class AlbumSidebarAllPhotosTile extends StatelessWidget {
  /// Creates the row.
  const AlbumSidebarAllPhotosTile({
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  /// Whether to draw the row as selected.
  final bool isSelected;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final radius = BorderRadius.circular(tokens.radiusMd);

    return InkWell(
      key: const ValueKey('album_sidebar_all_photos'),
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: radius,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingSm,
          vertical: tokens.spacingXs + tokens.spacingXs / 2,
        ),
        child: Row(
          children: [
            SizedBox(width: 16 + tokens.spacingXs),
            Icon(
              QuarkIcons.photo_library_outlined,
              size: 16,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: tokens.spacingSm),
            Expanded(
              child: Text(
                'All photos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
