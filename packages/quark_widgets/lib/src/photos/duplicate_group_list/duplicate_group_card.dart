import 'package:flutter/material.dart';

import '../../models/duplicate_group_item.dart';
import '../../models/duplicate_photo_item.dart';
import '../../theme/quark_tokens.dart';
import 'duplicate_photo_tile.dart';

/// One group in a `DuplicateGroupList`: a heading saying how alike its photos
/// are, and every copy as a `DuplicatePhotoTile`.
///
/// A group always keeps at least one copy, so once every other copy is marked
/// for deletion the last kept one cannot be tapped.
///
/// Key prefix: `duplicate_group_<id>` on the card.
///
/// ```dart
/// DuplicateGroupCard(
///   group: group,
///   selectedIds: selected,
///   thumbnailBuilder: thumbnailFor,
///   onToggle: toggle,
/// );
/// ```
class DuplicateGroupCard extends StatelessWidget {
  /// Creates the card.
  const DuplicateGroupCard({
    required this.group,
    required this.selectedIds,
    required this.thumbnailBuilder,
    required this.onToggle,
    super.key,
  });

  /// The group.
  final DuplicateGroupItem group;

  /// The ids marked for deletion, across every group.
  final Set<String> selectedIds;

  /// Builds a copy's thumbnail.
  final Widget Function(BuildContext context, DuplicatePhotoItem photo)
  thumbnailBuilder;

  /// Called with the id of a copy that was tapped.
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final kept = group.photos.where((p) => !selectedIds.contains(p.id)).length;

    return Card(
      key: ValueKey('duplicate_group_${group.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${group.isExact ? 'Identical copies' : 'Similar photos'}'
              ' · ${group.photos.length}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.foreground,
              ),
            ),
            if (!group.isExact)
              Text(
                'These look alike but may differ. Check before deleting.',
                style: TextStyle(fontSize: 12, color: tokens.mutedForeground),
              ),
            SizedBox(height: tokens.spacingSm),
            Wrap(
              spacing: tokens.spacingSm,
              runSpacing: tokens.spacingSm,
              children: [
                for (final photo in group.photos)
                  DuplicatePhotoTile(
                    photo: photo,
                    isSelected: selectedIds.contains(photo.id),
                    thumbnailBuilder: thumbnailBuilder,
                    onTap: !selectedIds.contains(photo.id) && kept <= 1
                        ? null
                        : () => onToggle(photo.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
