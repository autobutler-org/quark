import 'package:flutter/material.dart';

import '../models/duplicate_photo_item.dart';
import '../theme/quark_tokens.dart';

/// Asks before the copies marked on a duplicates page move to the trash,
/// naming every one with its location, including those scrolled out of view
/// (#3362), so the count on the button is never the only word on what goes.
///
/// The whole dialog scrolls when the list is longer than the window, so the
/// buttons stay reachable. It does not close itself: [onConfirm] and
/// [onCancel] fire, and the caller that pushed it pops it.
///
/// Key prefixes: `duplicate_delete_item_<id>` on each listed copy,
/// `duplicates_delete_confirm` and `duplicates_delete_cancel` on the buttons.
///
/// ```dart
/// showDialog<bool>(
///   context: context,
///   builder: (ctx) => DuplicateDeleteDialog(
///     photos: controller.selectedPhotos,
///     body: 'They move to Trash. You can restore them for 30 days.',
///     onConfirm: () => Navigator.of(ctx).pop(true),
///     onCancel: () => Navigator.of(ctx).pop(false),
///   ),
/// );
/// ```
class DuplicateDeleteDialog extends StatelessWidget {
  /// Creates the confirmation for [photos].
  const DuplicateDeleteDialog({
    required this.photos,
    required this.body,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  /// The copies about to move to the trash, in the order the page lists them.
  final List<DuplicatePhotoItem> photos;

  /// What deleting them does, written by the caller.
  final String body;

  /// Called when Move to Trash is tapped.
  final VoidCallback onConfirm;

  /// Called when Cancel is tapped.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final count = photos.length;

    return AlertDialog(
      scrollable: true,
      title: Text('Move $count ${count == 1 ? 'photo' : 'photos'} to Trash?'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(body),
          SizedBox(height: tokens.spacingMd),
          for (final photo in photos)
            Padding(
              key: ValueKey('duplicate_delete_item_${photo.id}'),
              padding: EdgeInsets.only(bottom: tokens.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.foreground,
                    ),
                  ),
                  Text(
                    photo.location,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('duplicates_delete_cancel'),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('duplicates_delete_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: tokens.error,
            foregroundColor: tokens.errorForeground,
          ),
          onPressed: onConfirm,
          child: const Text('Move to Trash'),
        ),
      ],
    );
  }
}
