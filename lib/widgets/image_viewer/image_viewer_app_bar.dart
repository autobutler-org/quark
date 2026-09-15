import 'package:flutter/material.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';

enum MoreAction {
  favorite,
  rotate,
  download,
  info,
  addToAlbum,
  removeFromAlbum,
  makeACopy,
  share,
  delete,
}

/// The photo viewer's top bar.
///
/// The bar carries the close button, the counter and the prev/next
/// chevrons at every width. Narrow screens have no room for the rest, so
/// favorite, rotate, download and info fold into the more menu instead of
/// crowding the close button (#1709).
class ImageViewerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDesktop;
  final int currentIndex;
  final int imageCount;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool isFavorite;
  final bool sidebarOpen;

  /// Path of the photo on the Quark, or null for a local device asset — the
  /// server actions only exist for the former.
  final String? relPath;

  /// Album the user navigated from, which turns "Add to Album" into
  /// "Remove from [PhotoAlbum.name]".
  final PhotoAlbum? sourceAlbum;

  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRotate;
  final VoidCallback onDownload;
  final VoidCallback onToggleSidebar;
  final VoidCallback onAddToAlbum;
  final VoidCallback onRemoveFromAlbum;
  final VoidCallback onMakeACopy;

  /// Opens the share sheet for the photo (#1911). Offered only for a photo on
  /// the Quark.
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onShowShortcuts;

  const ImageViewerAppBar({
    super.key,
    required this.isDesktop,
    required this.currentIndex,
    required this.imageCount,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    required this.isFavorite,
    required this.sidebarOpen,
    required this.relPath,
    required this.sourceAlbum,
    required this.onClose,
    required this.onToggleFavorite,
    required this.onRotate,
    required this.onDownload,
    required this.onToggleSidebar,
    required this.onAddToAlbum,
    required this.onRemoveFromAlbum,
    required this.onMakeACopy,
    required this.onShare,
    required this.onDelete,
    required this.onShowShortcuts,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final showNav = imageCount > 1;
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(QuarkIcons.close),
        tooltip: 'Close (Esc)',
        onPressed: onClose,
      ),
      title: showNav
          ? Text(
              '${currentIndex + 1} / $imageCount',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            )
          : null,
      actions: [
        if (showNav) ...[
          IconButton(
            icon: const Icon(QuarkIcons.chevron_left),
            tooltip: 'Previous (←)',
            onPressed: hasPrev ? onPrevious : null,
          ),
          IconButton(
            icon: const Icon(QuarkIcons.chevron_right),
            tooltip: 'Next (→)',
            onPressed: hasNext ? onNext : null,
          ),
          const SizedBox(width: 8),
        ],
        if (isDesktop) ...[
          Tooltip(
            message: 'Favorite (F)',
            child: IconButton(
              icon: Icon(
                isFavorite ? QuarkIcons.star : QuarkIcons.star_border,
                color: isFavorite
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white,
              ),
              onPressed: onToggleFavorite,
            ),
          ),
          Tooltip(
            message: 'Rotate 90° CW (R)',
            child: IconButton(
              icon: const Icon(QuarkIcons.rotate_90_degrees_cw_outlined),
              onPressed: onRotate,
            ),
          ),
          if (relPath != null)
            Tooltip(
              message: 'Download',
              child: IconButton(
                icon: const Icon(QuarkIcons.download_outlined),
                onPressed: onDownload,
              ),
            ),
          Tooltip(
            message: 'Info (I)',
            child: IconButton(
              icon: Icon(
                sidebarOpen ? QuarkIcons.info : QuarkIcons.info_outline,
                color: sidebarOpen
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white,
              ),
              onPressed: onToggleSidebar,
            ),
          ),
        ],
        if (!isDesktop || relPath != null)
          PopupMenuButton<MoreAction>(
            icon: const Icon(QuarkIcons.more_vert),
            color: const Color(0xFF1E1E1E),
            onSelected: (action) {
              switch (action) {
                case MoreAction.favorite:
                  onToggleFavorite();
                case MoreAction.rotate:
                  onRotate();
                case MoreAction.download:
                  onDownload();
                case MoreAction.info:
                  onToggleSidebar();
                case MoreAction.addToAlbum:
                  onAddToAlbum();
                case MoreAction.removeFromAlbum:
                  onRemoveFromAlbum();
                case MoreAction.makeACopy:
                  onMakeACopy();
                case MoreAction.share:
                  onShare();
                case MoreAction.delete:
                  onDelete();
              }
            },
            itemBuilder: (_) => [
              if (!isDesktop) ...[
                PopupMenuItem(
                  value: MoreAction.favorite,
                  child: Text(
                    isFavorite ? 'Unfavorite' : 'Favorite',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const PopupMenuItem(
                  value: MoreAction.rotate,
                  child: Text(
                    'Rotate 90° CW',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                if (relPath != null)
                  const PopupMenuItem(
                    value: MoreAction.download,
                    child: Text(
                      'Download',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                PopupMenuItem(
                  value: MoreAction.info,
                  child: Text(
                    sidebarOpen ? 'Hide info' : 'Show info',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
              if (relPath != null) ...[
                if (!isDesktop) const PopupMenuDivider(),
                if (sourceAlbum != null)
                  PopupMenuItem(
                    value: MoreAction.removeFromAlbum,
                    child: Text(
                      'Remove from ${sourceAlbum!.name}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  )
                else
                  const PopupMenuItem(
                    value: MoreAction.addToAlbum,
                    child: Text(
                      'Add to Album',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                const PopupMenuItem(
                  value: MoreAction.makeACopy,
                  child: Text(
                    'Make a Copy',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const PopupMenuItem(
                  value: MoreAction.share,
                  child: Text('Share…', style: TextStyle(color: Colors.white)),
                ),
                PopupMenuItem(
                  value: MoreAction.delete,
                  child: Text(
                    'Delete photo',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        // Keyboard shortcuts and the theme toggle need a keyboard and a wider
        // bar; on a phone they stay on the pages that have room for them.
        if (isDesktop) ...[
          Tooltip(
            message: 'Keyboard shortcuts (?)',
            child: IconButton(
              icon: const Icon(QuarkIcons.keyboard_outlined, size: 20),
              onPressed: onShowShortcuts,
            ),
          ),
          const SizedBox(width: 4),
          const AppThemeToggle(),
        ],
      ],
    );
  }
}
