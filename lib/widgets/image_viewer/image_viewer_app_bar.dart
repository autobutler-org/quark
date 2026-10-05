import 'package:flutter/material.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/image_viewer/image_viewer_more_menu.dart';
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

  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRotate;
  final VoidCallback onDownload;
  final VoidCallback onToggleSidebar;

  final VoidCallback onShowShortcuts;

  /// The "More options" menu. The page builds it, since a right-click on the
  /// photo opens the same one (#2276).
  final ImageViewerMoreMenu moreMenu;

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
    required this.onClose,
    required this.onToggleFavorite,
    required this.onRotate,
    required this.onDownload,
    required this.onToggleSidebar,
    required this.onShowShortcuts,
    required this.moreMenu,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    // The title is built here, above the bar's QuarkChrome.
    final tokens = QuarkTokens.of(context).onChrome;
    final showNav = imageCount > 1;
    return ChromeAppBar(
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
            if (!moreMenu.isEmpty)
              // A Builder for the button's own box, which the menu opens
              // under.
              Builder(
                builder: (context) => QuarkBarIconButton(
                  key: const ValueKey('image_viewer_more'),
                  icon: QuarkIcons.more_vert,
                  tooltip: 'More options',
                  onPressed: () =>
                      moreMenu.showAt(context, quarkMenuAnchor(context)),
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
