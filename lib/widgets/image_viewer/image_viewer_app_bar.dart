import 'package:material_ui/material_ui.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/image_viewer/image_viewer_more_menu.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo viewer's top bar.
///
/// Wide, it carries the close button, the "N / M" counter, the prev/next
/// chevrons and every photo action. On a phone it is the close button, the
/// file [name] with "3 of 12 · Nov 10" under it, and More (#4235): a swipe
/// turns the page, the row under the photo holds favorite and info, and
/// rotate and download fold into the more menu rather than crowd the close
/// button (#1709). The counter shows only with more than one photo, and the
/// date only when [date] is known.
class ImageViewerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDesktop;

  /// The photo's file name, the title on a phone.
  final String name;

  /// When the photo was taken, or its file date; null when neither is known.
  final DateTime? date;

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
    required this.name,
    required this.date,
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
    final textTheme = Theme.of(context).textTheme;
    final showNav = imageCount > 1;
    final date = this.date;
    final counter = isDesktop
        ? '${currentIndex + 1} / $imageCount'
        : '${currentIndex + 1} of $imageCount';
    final subtitle = [
      if (showNav) counter,
      if (date != null) '${CalendarLabels.monthShort(date.month)} ${date.day}',
    ].join(' · ');
    return ChromeAppBar(
      leading: Center(
        child: QuarkBarIconButton(
          key: const ValueKey('image_viewer_close'),
          icon: QuarkIcons.close,
          tooltip: 'Close (Esc)',
          onPressed: onClose,
        ),
      ),
      title: isDesktop
          ? (showNav
                ? Text(
                    counter,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.secondaryForeground,
                    ),
                  )
                : null)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  key: const ValueKey('image_viewer_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: tokens.foreground,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    key: const ValueKey('image_viewer_subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.secondaryForeground,
                    ),
                  ),
              ],
            ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: QuarkTokens.of(context).spacingSm,
          children: [
            if (isDesktop) ...[
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
            // Keyboard shortcuts need a keyboard and a wider bar.
            if (isDesktop) ...[
              QuarkBarIconButton(
                key: const ValueKey('image_viewer_shortcuts'),
                icon: QuarkIcons.keyboard_outlined,
                tooltip: 'Keyboard shortcuts (?)',
                onPressed: onShowShortcuts,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
