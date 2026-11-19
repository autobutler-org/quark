import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_icon_button.dart';
import '../layout/quark_bar_menu_button.dart';
import '../theme/quark_tokens.dart';

/// The bar that sits at the bottom of the photo grid while photos are being
/// selected: a count, Add to album, and every other action a single photo
/// has, run on the whole selection (#4154).
///
/// Leaving selection is the top bar's job — the same `FileSelectionBar` close
/// button Files and the trash use — so this bar carries no Cancel (#2311).
///
/// Every action but Add to album is optional: a null callback leaves it out.
/// The favorite action reads Unfavorite when [allFavorites] is true. Share
/// is passed only while the share sheet can take the selection, and Remove
/// from album only where the grid shows an album; [removeFromAlbumLabel]
/// words it, "Remove from favorites" in Favorites.
///
/// [quarkOnlyDisabledReason] disables every action except Add to album, for a
/// selection holding a photo only the phone has, and is the tooltip that says
/// why. Every action is disabled at a count of zero.
///
/// At [collapseBelow] and narrower, only the count and Add to album stay in
/// the row and the rest move into a menu labeled More.
///
/// Key prefixes: `photo_selection_add_to_album`, `photo_selection_slideshow`,
/// `photo_selection_favorite`, `photo_selection_download`,
/// `photo_selection_share`, `photo_selection_copy`,
/// `photo_selection_remove_from_album`, `photo_selection_delete`, and `photo_selection_more` on the More menu.
///
/// ```dart
/// PhotoSelectionBar(
///   selectedCount: controller.selectedIds.length,
///   onAddToAlbum: () => showAlbumPicker(context),
///   allFavorites: controller.selectionAllFavorites,
///   onFavorite: controller.favoriteSelected,
///   onDelete: confirmAndDelete,
/// );
/// ```
class PhotoSelectionBar extends StatelessWidget {
  /// Creates the selection bar for [selectedCount] photos.
  const PhotoSelectionBar({
    required this.selectedCount,
    required this.onAddToAlbum,
    this.allFavorites = false,
    this.onSlideshow,
    this.onFavorite,
    this.onDownload,
    this.onShare,
    this.onCopy,
    this.onRemoveFromAlbum,
    this.removeFromAlbumLabel = 'Remove from album',
    this.onDelete,
    this.quarkOnlyDisabledReason,
    super.key,
  });

  /// The width at and below which the actions after Add to album collapse
  /// into the More menu.
  static const double collapseBelow = 600;

  /// How many photos are selected, shown at the start of the bar.
  final int selectedCount;

  /// Opens the album picker. Not called while [selectedCount] is zero.
  final VoidCallback onAddToAlbum;

  /// Whether every selected photo is already a favorite, which words the
  /// favorite action Unfavorite.
  final bool allFavorites;

  /// Plays the selection as a slideshow. Null leaves the action out.
  final VoidCallback? onSlideshow;

  /// Favorites the selection, or takes it out of Favorites when [allFavorites]. Null
  /// leaves the action out.
  final VoidCallback? onFavorite;

  /// Downloads the selection, which the app saves as one zip. Null leaves
  /// the action out.
  final VoidCallback? onDownload;

  /// Opens the share sheet for the selection. Null leaves the action out.
  final VoidCallback? onShare;

  /// Makes a copy of every selected photo. Null leaves the action out.
  final VoidCallback? onCopy;

  /// Takes the selection out of the album showing. Null leaves the action
  /// out.
  final VoidCallback? onRemoveFromAlbum;

  /// The words on [onRemoveFromAlbum]'s action.
  final String removeFromAlbumLabel;

  /// Moves the selection to the trash. Null leaves the action out.
  final VoidCallback? onDelete;

  /// Why the actions only a Quark photo can take are off, shown as their
  /// tooltip; null when they are on.
  final String? quarkOnlyDisabledReason;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final reason = quarkOnlyDisabledReason;
    final enabled = selectedCount > 0 && reason == null;

    final actions =
        <({String key, IconData icon, String label, VoidCallback? onPressed})>[
          if (onSlideshow case final onSlideshow?)
            (
              key: 'photo_selection_slideshow',
              icon: QuarkIcons.play_arrow,
              label: 'Slideshow',
              onPressed: onSlideshow,
            ),
          if (onFavorite case final onFavorite?)
            (
              key: 'photo_selection_favorite',
              icon: allFavorites ? QuarkIcons.star : QuarkIcons.star_border,
              label: allFavorites ? 'Unfavorite' : 'Favorite',
              onPressed: onFavorite,
            ),
          if (onDownload case final onDownload?)
            (
              key: 'photo_selection_download',
              icon: QuarkIcons.download_outlined,
              label: 'Download',
              onPressed: onDownload,
            ),
          if (onShare case final onShare?)
            (
              key: 'photo_selection_share',
              icon: QuarkIcons.share_outlined,
              label: 'Share…',
              onPressed: onShare,
            ),
          if (onCopy case final onCopy?)
            (
              key: 'photo_selection_copy',
              icon: QuarkIcons.content_copy,
              label: 'Make copies',
              onPressed: onCopy,
            ),
          if (onRemoveFromAlbum case final onRemove?)
            (
              key: 'photo_selection_remove_from_album',
              icon: QuarkIcons.remove_circle_outline,
              label: removeFromAlbumLabel,
              onPressed: onRemove,
            ),
          if (onDelete case final onDelete?)
            (
              key: 'photo_selection_delete',
              icon: QuarkIcons.delete_outline,
              label: 'Delete',
              onPressed: onDelete,
            ),
        ];

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
          vertical: tokens.spacingXs,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final collapsed = constraints.maxWidth <= collapseBelow;
            // `spaceBetween` rather than a Spacer: it keeps the actions flush
            // right while leaving Add to album the only flexible action, so
            // it gives up label width instead of overflowing the row on a
            // narrow phone (#1599).
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '$selectedCount ${selectedCount == 1 ? 'photo' : 'photos'} '
                    'selected',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.secondaryForeground,
                      // Equal-width digits, so the label does not shift as
                      // each tap changes the count.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Flexible(
                  flex: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: FilledButton(
                          key: const ValueKey('photo_selection_add_to_album'),
                          onPressed: selectedCount > 0 ? onAddToAlbum : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                QuarkIcons.photo_album_outlined,
                                size: 16,
                              ),
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
                      if (actions.isNotEmpty && collapsed)
                        QuarkBarMenuButton(
                          buttonKey: const ValueKey('photo_selection_more'),
                          icon: QuarkIcons.more_vert,
                          label: 'More',
                          keepLabel: true,
                          tooltip: reason,
                          enabled: enabled,
                          menuChildren: [
                            for (final action in actions)
                              MenuItemButton(
                                key: ValueKey(action.key),
                                leadingIcon: Icon(action.icon),
                                onPressed: action.onPressed,
                                child: Text(action.label),
                              ),
                          ],
                        ),
                      if (!collapsed)
                        for (final action in actions)
                          QuarkBarIconButton(
                            key: ValueKey(action.key),
                            icon: action.icon,
                            tooltip: reason ?? action.label,
                            destructive: action.key == 'photo_selection_delete',
                            onPressed: enabled ? action.onPressed : null,
                          ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
