import 'package:flutter/material.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
    final tokens = QuarkTokens.of(context);
    final showNav = imageCount > 1;
    return AppBar(
      leading: Center(
        child: QuarkBarIconButton(
          key: const ValueKey('image_viewer_close'),
          icon: QuarkIcons.close,
          tooltip: 'Close (Esc)',
          onPressed: onClose,
        ),
      ),
      title: showNav
          ? Text(
              '${currentIndex + 1} / $imageCount',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.secondaryForeground,
              ),
            )
          : null,
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: QuarkTokens.of(context).spacingSm,
          children: [
            if (showNav) ...[
              QuarkBarIconButton(
                key: const ValueKey('image_viewer_previous'),
                icon: QuarkIcons.chevron_left,
                tooltip: 'Previous (←)',
                onPressed: hasPrev ? onPrevious : null,
              ),
              QuarkBarIconButton(
                key: const ValueKey('image_viewer_next'),
                icon: QuarkIcons.chevron_right,
                tooltip: 'Next (→)',
                onPressed: hasNext ? onNext : null,
              ),
            ],
            if (isDesktop) ...[
              QuarkBarIconButton(
                key: const ValueKey('image_viewer_favorite'),
                icon: isFavorite ? QuarkIcons.star : QuarkIcons.star_border,
                tooltip: 'Favorite (F)',
                onPressed: onToggleFavorite,
              ),
              QuarkBarIconButton(
                key: const ValueKey('image_viewer_rotate'),
                icon: QuarkIcons.rotate_90_degrees_cw_outlined,
                tooltip: 'Rotate 90° CW (R)',
                onPressed: onRotate,
              ),
              if (relPath != null)
                QuarkBarIconButton(
                  key: const ValueKey('image_viewer_download'),
                  icon: QuarkIcons.download_outlined,
                  tooltip: 'Download',
                  onPressed: onDownload,
                ),
              QuarkBarIconButton(
                key: const ValueKey('image_viewer_info'),
                icon: sidebarOpen ? QuarkIcons.info : QuarkIcons.info_outline,
                tooltip: 'Info (I)',
                onPressed: onToggleSidebar,
              ),
            ],
            if (!isDesktop || relPath != null)
              MenuAnchor(
                menuChildren: [
                  if (!isDesktop) ...[
                    MenuItemButton(
                      onPressed: onToggleFavorite,
                      child: Text(isFavorite ? 'Unfavorite' : 'Favorite'),
                    ),
                    MenuItemButton(
                      onPressed: onRotate,
                      child: const Text('Rotate 90° CW'),
                    ),
                    if (relPath != null)
                      MenuItemButton(
                        onPressed: onDownload,
                        child: const Text('Download'),
                      ),
                    MenuItemButton(
                      onPressed: onToggleSidebar,
                      child: Text(sidebarOpen ? 'Hide info' : 'Show info'),
                    ),
                  ],
                  if (relPath != null) ...[
                    if (!isDesktop) const Divider(height: 1),
                    if (sourceAlbum != null)
                      MenuItemButton(
                        onPressed: onRemoveFromAlbum,
                        child: Text('Remove from ${sourceAlbum!.name}'),
                      )
                    else
                      MenuItemButton(
                        onPressed: onAddToAlbum,
                        child: const Text('Add to Album'),
                      ),
                    MenuItemButton(
                      onPressed: onMakeACopy,
                      child: const Text('Make a Copy'),
                    ),
                    MenuItemButton(
                      onPressed: onShare,
                      child: const Text('Share…'),
                    ),
                    MenuItemButton(
                      onPressed: onDelete,
                      style: MenuItemButton.styleFrom(
                        foregroundColor: tokens.error,
                      ),
                      child: const Text('Delete photo'),
                    ),
                  ],
                ],
                builder: (context, controller, _) => QuarkBarIconButton(
                  key: const ValueKey('image_viewer_more'),
                  icon: QuarkIcons.more_vert,
                  tooltip: 'More options',
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
              ),
            // Keyboard shortcuts and the theme toggle need a keyboard and a
            // wider bar; on a phone they stay on the pages that have room.
            if (isDesktop) ...[
              QuarkBarIconButton(
                key: const ValueKey('image_viewer_shortcuts'),
                icon: QuarkIcons.keyboard_outlined,
                tooltip: 'Keyboard shortcuts (?)',
                onPressed: onShowShortcuts,
              ),
              const AppThemeToggle(),
            ],
          ],
        ),
      ],
    );
  }
}
