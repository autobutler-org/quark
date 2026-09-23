import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// The bar that sits at the bottom of the photo grid while photos are being
/// selected: a count and the add-to-album action.
///
/// Leaving selection is the top bar's job — the same `FileSelectionBar` close
/// button Files and the trash use — so this bar no longer carries a second
/// Cancel (#2311).
///
/// Adding is disabled at a count of zero, so the button never opens a picker
/// that would do nothing.
///
/// Key prefixes: `photo_selection_add_to_album`.
///
/// ```dart
/// PhotoSelectionBar(
///   selectedCount: controller.selectedKeys.length,
///   onAddToAlbum: () => showAlbumPicker(context),
/// );
/// ```
class PhotoSelectionBar extends StatelessWidget {
  /// Creates the selection bar for [selectedCount] photos.
  const PhotoSelectionBar({
    required this.selectedCount,
    required this.onAddToAlbum,
    super.key,
  });

  /// How many photos are selected, shown in the middle of the bar.
  final int selectedCount;

  /// Opens the album picker. Not called while [selectedCount] is zero.
  final VoidCallback onAddToAlbum;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outline)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingMd,
          vertical: tokens.spacingSm + tokens.spacingXs,
        ),
        // `spaceBetween` rather than a pair of `Spacer`s: it keeps the action
        // flush right while leaving the button the only flexible child, which
        // is what lets it give up label width instead of overflowing the row
        // on a narrow phone (#1599).
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '$selectedCount ${selectedCount == 1 ? 'photo' : 'photos'} '
                'selected',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.secondaryForeground,
                ),
              ),
            ),
            Flexible(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('photo_selection_add_to_album'),
                onPressed: selectedCount > 0 ? onAddToAlbum : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(QuarkIcons.photo_album_outlined, size: 16),
                    SizedBox(width: tokens.spacingSm),
                    const Flexible(
                      child: Text(
                        'Add to Album',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
