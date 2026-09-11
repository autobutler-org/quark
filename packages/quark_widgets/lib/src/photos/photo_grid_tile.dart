import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/photo_item.dart';
import 'live_badge.dart';

/// One square of a photo grid: the thumbnail, a live badge, a favorite star,
/// and the selection chrome while photos are being selected.
///
/// The tile only reports gestures. What a tap means — opening the photo or
/// toggling it in the selection — is the caller's decision, so [onTap],
/// [onLongPress] and [onDoubleTap] fire the same way in and out of
/// [selectionMode]. [selectionMode] and [isSelected] only change what is drawn:
/// a dim over every unselected photo, a primary border around every selected
/// one, and a checkbox in the corner.
///
/// The thumbnail comes from [thumbnailBuilder], because drawing one needs the
/// network or a device API the package does not depend on.
///
/// The overlay colors are fixed rather than themed on purpose: like
/// [LiveBadge], they are drawn on top of a photograph, not on a surface.
///
/// Key prefixes: `photo_tile_<id>` on the tile and `photo_tile_check_<id>` on
/// the selection checkbox, which is only rendered in [selectionMode].
///
/// ```dart
/// PhotoGridTile(
///   item: photo,
///   isSelected: controller.selectedIds.contains(photo.id),
///   selectionMode: controller.selectionMode,
///   thumbnailBuilder: (context, photo) => Image.network(urlFor(photo)),
///   onTap: () => open(photo),
///   onLongPress: () => controller.toggleSelection(photo.id),
/// );
/// ```
class PhotoGridTile extends StatelessWidget {
  /// Creates the tile for [item].
  const PhotoGridTile({
    required this.item,
    required this.thumbnailBuilder,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = false,
    this.selectionMode = false,
    this.onDoubleTap,
    super.key,
  });

  /// The photo this tile shows.
  final PhotoItem item;

  /// Builds the thumbnail that fills the tile.
  final Widget Function(BuildContext context, PhotoItem item) thumbnailBuilder;

  /// Whether [item] is in the selection. Draws the border and fills the
  /// checkbox, in [selectionMode] only.
  final bool isSelected;

  /// Whether photos are being selected. Draws the dim and the checkbox, and
  /// hides the favorite star so the two do not compete.
  final bool selectionMode;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  /// Called when the tile is long-pressed.
  final VoidCallback onLongPress;

  /// Called when the tile is double-tapped. Null leaves double tap
  /// unrecognized, which keeps a single tap from waiting to see whether a
  /// second one follows.
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: selectionMode ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('photo_tile_${item.id}'),
        onTap: onTap,
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            thumbnailBuilder(context, item),
            if (item.hasLiveVideo)
              const Positioned(top: 4, left: 4, child: LiveBadge()),
            if (item.isFavorite && !selectionMode)
              const Positioned(
                bottom: 4,
                right: 4,
                child: Icon(
                  QuarkIcons.star_rounded,
                  size: 16,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            if (selectionMode && !isSelected)
              ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
            if (selectionMode && isSelected)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.primary, width: 3),
                ),
              ),
            if (selectionMode)
              Positioned(
                top: 6,
                left: 6,
                child: AnimatedContainer(
                  key: ValueKey('photo_tile_check_${item.id}'),
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : Colors.white.withValues(alpha: 0.8),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          QuarkIcons.check,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
