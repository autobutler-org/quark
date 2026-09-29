import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../models/duplicate_photo_item.dart';
import '../../theme/quark_tokens.dart';

/// One copy in a `DuplicateGroupCard`: its thumbnail, a badge saying whether
/// it is kept or deleted, and its name and location underneath.
///
/// Key prefix: `duplicate_photo_<id>` on the tappable thumbnail.
///
/// ```dart
/// DuplicatePhotoTile(
///   photo: photo,
///   isSelected: false,
///   thumbnailBuilder: thumbnailFor,
///   onTap: () => toggle(photo.id),
/// );
/// ```
class DuplicatePhotoTile extends StatelessWidget {
  /// Creates the tile.
  const DuplicatePhotoTile({
    required this.photo,
    required this.isSelected,
    required this.thumbnailBuilder,
    required this.onTap,
    super.key,
  });

  /// The copy.
  final DuplicatePhotoItem photo;

  /// Whether the copy is marked for deletion.
  final bool isSelected;

  /// Builds the thumbnail.
  final Widget Function(BuildContext context, DuplicatePhotoItem photo)
  thumbnailBuilder;

  /// Called when the thumbnail is tapped. Null disables the tile, for
  /// the last copy a group keeps.
  final VoidCallback? onTap;

  /// The tile's width, thumbnail included.
  static const double width = 128;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final accent = isSelected ? tokens.error : tokens.primary;
    final radius = BorderRadius.circular(tokens.radiusMd);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: onTap != null,
            selected: isSelected,
            label: isSelected ? 'Delete ${photo.name}' : 'Keep ${photo.name}',
            child: InkWell(
              key: ValueKey('duplicate_photo_${photo.id}'),
              onTap: onTap,
              borderRadius: radius,
              child: ClipRRect(
                borderRadius: radius,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      thumbnailBuilder(context, photo),
                      if (isSelected)
                        ColoredBox(color: tokens.error.withValues(alpha: 0.25)),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: isSelected ? accent : tokens.border,
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                      ),
                      Positioned(
                        left: tokens.spacingXs,
                        bottom: tokens.spacingXs,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: tokens.spacingSm,
                              vertical: tokens.spacingXs / 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected
                                      ? QuarkIcons.delete_outline
                                      : QuarkIcons.check_rounded,
                                  size: 12,
                                  color: isSelected
                                      ? tokens.errorForeground
                                      : tokens.primaryForeground,
                                ),
                                SizedBox(width: tokens.spacingXs),
                                Text(
                                  isSelected ? 'Delete' : 'Keep',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? tokens.errorForeground
                                        : tokens.primaryForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.spacingXs),
          Text(
            photo.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: tokens.foreground),
          ),
          Text(
            photo.location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: tokens.mutedForeground),
          ),
        ],
      ),
    );
  }
}
