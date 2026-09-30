import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The menu on a photo while an album is showing: add it to another album,
/// and take it out of this one when the album allows that. The tile's
/// `more_vert` button, a right-click and a long press all open it, at the
/// pointer, the way a row's menu opens in Files (#2245, #2260).
///
/// Leave [onRemoveFromFavorites] and [onRemoveFromAlbum] null to hide them:
/// only Favorites offers the first, only a user album the second, since the
/// Quark fills other system albums itself (#992).
///
/// The menu closes before an entry fires, so the next sheet or dialog opens
/// over the page rather than over the menu.
///
/// Key prefixes: `album_item_action_add`, `album_item_action_unfavorite` and
/// `album_item_action_remove` on the entries.
@immutable
class AlbumItemMenu {
  /// Creates the menu.
  const AlbumItemMenu({
    required this.onAddToAnotherAlbum,
    this.onRemoveFromFavorites,
    this.onRemoveFromAlbum,
  });

  /// Opens the album picker for this photo.
  final VoidCallback onAddToAnotherAlbum;

  /// Un-stars the photo, which takes it out of Favorites.
  final VoidCallback? onRemoveFromFavorites;

  /// Takes the photo out of this album.
  final VoidCallback? onRemoveFromAlbum;

  /// Opens the menu at [globalPosition].
  Future<void> showAt(BuildContext context, Offset globalPosition) {
    final onRemoveFromFavorites = this.onRemoveFromFavorites;
    final onRemoveFromAlbum = this.onRemoveFromAlbum;
    return showQuarkMenu(
      context,
      position: globalPosition,
      entries: [
        QuarkMenuEntry(
          key: const ValueKey('album_item_action_add'),
          label: 'Add to another album',
          icon: QuarkIcons.photo_album_outlined,
          onSelected: onAddToAnotherAlbum,
        ),
        if (onRemoveFromFavorites != null)
          QuarkMenuEntry(
            key: const ValueKey('album_item_action_unfavorite'),
            label: 'Remove from favorites',
            icon: QuarkIcons.star_rounded,
            onSelected: onRemoveFromFavorites,
          ),
        if (onRemoveFromAlbum != null)
          QuarkMenuEntry(
            key: const ValueKey('album_item_action_remove'),
            label: 'Remove from album',
            icon: QuarkIcons.remove_circle_outline,
            destructive: true,
            onSelected: onRemoveFromAlbum,
          ),
      ],
    );
  }
}
