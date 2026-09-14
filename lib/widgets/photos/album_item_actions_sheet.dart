import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The menu a long-pressed photo opens while an album is showing: add it to
/// another album, and take it out of this one when the album allows that.
///
/// Leave [onRemoveFromFavorites] and [onRemoveFromAlbum] null to hide them:
/// only Favorites offers the first, only a user album the second, since the
/// Quark fills other system albums itself (#992).
///
/// Each entry closes the sheet before it fires, so the next sheet or dialog
/// opens over the page rather than over the menu.
class AlbumItemActionsSheet extends StatelessWidget {
  /// Creates the menu.
  const AlbumItemActionsSheet({
    required this.onAddToAnotherAlbum,
    this.onRemoveFromFavorites,
    this.onRemoveFromAlbum,
    super.key,
  });

  /// Shows the menu as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onAddToAnotherAlbum,
    VoidCallback? onRemoveFromFavorites,
    VoidCallback? onRemoveFromAlbum,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuarkColors.radiusLg),
      ),
      builder: (_) => AlbumItemActionsSheet(
        onAddToAnotherAlbum: onAddToAnotherAlbum,
        onRemoveFromFavorites: onRemoveFromFavorites,
        onRemoveFromAlbum: onRemoveFromAlbum,
      ),
    );
  }

  /// Opens the album picker for this photo.
  final VoidCallback onAddToAnotherAlbum;

  /// Un-stars the photo, which takes it out of Favorites.
  final VoidCallback? onRemoveFromFavorites;

  /// Takes the photo out of this album.
  final VoidCallback? onRemoveFromAlbum;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final onRemoveFromFavorites = this.onRemoveFromFavorites;
    final onRemoveFromAlbum = this.onRemoveFromAlbum;
    void closeThen(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('album_item_action_add'),
            leading: const Icon(QuarkIcons.photo_album_outlined),
            title: const Text('Add to another album'),
            onTap: () => closeThen(onAddToAnotherAlbum),
          ),
          if (onRemoveFromFavorites != null)
            ListTile(
              key: const ValueKey('album_item_action_unfavorite'),
              leading: const Icon(QuarkIcons.star_rounded),
              title: const Text('Remove from favorites'),
              onTap: () => closeThen(onRemoveFromFavorites),
            ),
          if (onRemoveFromAlbum != null)
            ListTile(
              key: const ValueKey('album_item_action_remove'),
              leading: Icon(QuarkIcons.remove_circle_outline, color: error),
              title: Text('Remove from album', style: TextStyle(color: error)),
              onTap: () => closeThen(onRemoveFromAlbum),
            ),
        ],
      ),
    );
  }
}
