import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo viewer's "More options" menu, opened at the pointer from the
/// bar's `more_vert` button the way every item's menu opens (#2267).
///
/// With [includeBarActions] it also offers favorite, rotate, download and
/// info, which a narrow bar has no room for (#1709). The server actions only
/// exist for a photo on the Quark, which is when [relPath] is set. A HEIC
/// photo there also offers "Download as JPEG" (#4188).
///
/// Key prefix: `image_viewer_more_<action>` on each entry.
@immutable
class ImageViewerMoreMenu {
  /// Creates the menu.
  const ImageViewerMoreMenu({
    required this.includeBarActions,
    required this.isFavorite,
    required this.sidebarOpen,
    required this.relPath,
    required this.sourceAlbum,
    required this.onToggleFavorite,
    required this.onRotate,
    required this.onDownload,
    required this.onToggleSidebar,
    required this.onAddToAlbum,
    required this.onRemoveFromAlbum,
    required this.onCopy,
    required this.copyUnavailableReason,
    required this.onDuplicate,
    required this.onShare,
    required this.onDelete,
    this.onDownloadAsJpeg,
  });

  /// Whether to offer the actions a wide bar shows as buttons.
  final bool includeBarActions;
  final bool isFavorite;
  final bool sidebarOpen;

  /// Path of the photo on the Quark, or null for a local device asset.
  final String? relPath;

  /// Album the user navigated from, which turns "Add to Album" into
  /// "Remove from [PhotoAlbum.name]".
  final PhotoAlbum? sourceAlbum;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRotate;
  final VoidCallback onDownload;
  final VoidCallback onToggleSidebar;
  final VoidCallback onAddToAlbum;
  final VoidCallback onRemoveFromAlbum;

  /// Copies the photo showing to the system clipboard (#3436).
  final VoidCallback onCopy;

  /// Why the clipboard cannot take a photo here, or null when it can. While
  /// set, the Copy entry is disabled.
  final String? copyUnavailableReason;

  /// Duplicates the photo on the Quark, beside the original.
  final VoidCallback onDuplicate;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  /// Saves a JPEG copy of a HEIC photo (#4188), or null to leave the entry
  /// out, as for every other format.
  final VoidCallback? onDownloadAsJpeg;

  /// Whether the menu has anything to offer.
  bool get isEmpty => !includeBarActions && relPath == null;

  /// The menu's rows, in order.
  List<QuarkMenuEntry> get entries {
    final sourceAlbum = this.sourceAlbum;
    QuarkMenuEntry entry(
      String id,
      String label,
      VoidCallback? onSelected, {
      bool destructive = false,
    }) => QuarkMenuEntry(
      key: ValueKey('image_viewer_more_$id'),
      label: label,
      destructive: destructive,
      onSelected: onSelected,
    );

    return [
      if (includeBarActions) ...[
        entry(
          'favorite',
          isFavorite ? 'Unfavorite' : 'Favorite',
          onToggleFavorite,
        ),
        entry('rotate', 'Rotate 90° CW', onRotate),
        if (relPath != null) entry('download', 'Download', onDownload),
        entry('info', sidebarOpen ? 'Hide info' : 'Show info', onToggleSidebar),
      ],
      if (relPath != null) ...[
        if (includeBarActions) const QuarkMenuEntry.divider(),
        if (onDownloadAsJpeg != null)
          entry('download_jpeg', 'Download as JPEG', onDownloadAsJpeg),
        if (sourceAlbum != null)
          entry(
            'remove_from_album',
            'Remove from ${sourceAlbum.name}',
            onRemoveFromAlbum,
          )
        else
          entry('add_to_album', 'Add to Album', onAddToAlbum),
        entry('copy', 'Copy', copyUnavailableReason == null ? onCopy : null),
        entry('duplicate', 'Duplicate', onDuplicate),
        entry('share', 'Share…', onShare),
        entry('delete', 'Delete photo', onDelete, destructive: true),
      ],
    ];
  }

  /// Opens the menu at [globalPosition].
  Future<void> showAt(BuildContext context, Offset globalPosition) =>
      showQuarkMenu(context, position: globalPosition, entries: entries);
}
