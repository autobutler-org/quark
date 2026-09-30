import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The menu on a Quark photo in the library, outside any album (#2276): the
/// single-photo actions the image viewer offers, minus the ones that only
/// mean something there (Info, Rotate) or in an album (Remove from album).
///
/// The tile's `more_vert` button and a right-click open it at the pointer. A
/// long press stays selection, as it always has in the library.
///
/// Key prefix: `library_photo_action_<action>` on the entries.
@immutable
class LibraryPhotoMenu {
  /// Creates the menu.
  const LibraryPhotoMenu({
    required this.isFavorite,
    required this.onAddToAlbum,
    required this.onToggleFavorite,
    required this.onDownload,
    required this.onShare,
    required this.onMakeACopy,
    required this.onDelete,
  });

  /// Whether the photo is starred, which words the favorite entry.
  final bool isFavorite;
  final VoidCallback onAddToAlbum;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final VoidCallback onMakeACopy;
  final VoidCallback onDelete;

  /// Opens the menu at [globalPosition].
  Future<void> showAt(BuildContext context, Offset globalPosition) =>
      showQuarkMenu(
        context,
        position: globalPosition,
        entries: [
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_add_to_album'),
            label: 'Add to album',
            icon: QuarkIcons.photo_album_outlined,
            onSelected: onAddToAlbum,
          ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_favorite'),
            label: isFavorite ? 'Unfavorite' : 'Favorite',
            icon: isFavorite ? QuarkIcons.star_rounded : QuarkIcons.star_border,
            onSelected: onToggleFavorite,
          ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_download'),
            label: 'Download',
            icon: QuarkIcons.download_outlined,
            onSelected: onDownload,
          ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_share'),
            label: 'Share…',
            icon: QuarkIcons.share_outlined,
            onSelected: onShare,
          ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_copy'),
            label: 'Make a copy',
            icon: QuarkIcons.copy_outlined,
            onSelected: onMakeACopy,
          ),
          const QuarkMenuEntry.divider(),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_delete'),
            label: 'Delete',
            icon: QuarkIcons.delete_outline,
            destructive: true,
            onSelected: onDelete,
          ),
        ],
      );
}
