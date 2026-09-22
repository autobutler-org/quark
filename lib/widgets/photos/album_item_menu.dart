import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

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
    final error = Theme.of(context).colorScheme.error;
    final onRemoveFromFavorites = this.onRemoveFromFavorites;
    final onRemoveFromAlbum = this.onRemoveFromAlbum;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    return showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<void>(
          key: const ValueKey('album_item_action_add'),
          onTap: onAddToAnotherAlbum,
          child: const ListTile(
            leading: Icon(QuarkIcons.photo_album_outlined),
            title: Text('Add to another album'),
          ),
        ),
        if (onRemoveFromFavorites != null)
          PopupMenuItem<void>(
            key: const ValueKey('album_item_action_unfavorite'),
            onTap: onRemoveFromFavorites,
            child: const ListTile(
              leading: Icon(QuarkIcons.star_rounded),
              title: Text('Remove from favorites'),
            ),
          ),
        if (onRemoveFromAlbum != null)
          PopupMenuItem<void>(
            key: const ValueKey('album_item_action_remove'),
            onTap: onRemoveFromAlbum,
            child: ListTile(
              leading: Icon(QuarkIcons.remove_circle_outline, color: error),
              title: Text('Remove from album', style: TextStyle(color: error)),
            ),
          ),
      ],
    );
  }
}
