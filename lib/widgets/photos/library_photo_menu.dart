import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The menu on a Quark photo in the library, outside any album (#2276): the
/// single-photo actions the image viewer offers, minus the ones that only
/// mean something there (Info, Rotate) or in an album (Remove from album).
///
/// The tile's `more_vert` button and a right-click open it at the pointer. A
/// long press stays selection, as it always has in the library.
///
/// A HEIC photo also offers **Download as JPEG**, a copy the other side can
/// open (#4188).
///
/// **Copy** puts the image on the system clipboard; **Duplicate** makes a
/// second file on the Quark (#3436).
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
    required this.onCopy,
    required this.copyUnavailableReason,
    required this.onDuplicate,
    required this.onDelete,
    this.onDownloadAsJpeg,
  });

  /// Whether the photo is starred, which words the favorite entry.
  final bool isFavorite;
  final VoidCallback onAddToAlbum;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDownload;

  /// Saves a JPEG copy of a HEIC photo (#4188), or null to leave the entry
  /// out, as for every other format.
  final VoidCallback? onDownloadAsJpeg;
  final VoidCallback onShare;

  /// Copies the photo to the system clipboard (#3436).
  final VoidCallback onCopy;

  /// Why the clipboard cannot take a photo here, or null when it can. While
  /// set, the Copy entry is disabled.
  final String? copyUnavailableReason;

  /// Duplicates the photo on the Quark, beside the original.
  final VoidCallback onDuplicate;
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
            icon: isFavorite ? QuarkIcons.star : QuarkIcons.star_border,
            onSelected: onToggleFavorite,
          ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_download'),
            label: 'Download',
            icon: QuarkIcons.download_outlined,
            onSelected: onDownload,
          ),
          if (onDownloadAsJpeg != null)
            QuarkMenuEntry(
              key: const ValueKey('library_photo_action_download_jpeg'),
              label: 'Download as JPEG',
              icon: QuarkIcons.download_outlined,
              onSelected: onDownloadAsJpeg,
            ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_share'),
            label: 'Share…',
            icon: QuarkIcons.share_outlined,
            onSelected: onShare,
          ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_copy'),
            label: 'Copy',
            icon: QuarkIcons.content_copy,
            onSelected: copyUnavailableReason == null ? onCopy : null,
          ),
          QuarkMenuEntry(
            key: const ValueKey('library_photo_action_duplicate'),
            label: 'Duplicate',
            icon: QuarkIcons.duplicate,
            onSelected: onDuplicate,
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
