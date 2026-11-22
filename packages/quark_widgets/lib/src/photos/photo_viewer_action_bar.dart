import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// The row of actions under a full-screen photo on a phone: Share, Favorite,
/// Info and Delete, each a glyph over its label, within thumb reach (#4235).
///
/// Every action is optional: a null callback leaves it out, so a photo only
/// the phone has, with nothing to share or delete on a Quark, still gets its
/// Info. Favorite reads Unfavorite with a filled star while [isFavorite], and
/// Info draws a filled glyph and is announced as selected while [infoOpen].
///
/// Its colors are fixed rather than themed, as [LiveBadge]'s are: the viewer
/// is black in light mode too, so white is what stays readable on it. Each
/// action answers taps across at least a 44 x 44 square, and the bar keeps
/// clear of the bottom system inset.
///
/// Key prefixes: `photo_viewer_action_share`, `photo_viewer_action_favorite`,
/// `photo_viewer_action_info`, `photo_viewer_action_delete`.
///
/// ```dart
/// PhotoViewerActionBar(
///   isFavorite: isFavorite,
///   infoOpen: infoOpen,
///   onShare: share,
///   onFavorite: toggleFavorite,
///   onInfo: toggleInfo,
///   onDelete: confirmDelete,
/// );
/// ```
class PhotoViewerActionBar extends StatelessWidget {
  /// Creates the action row.
  const PhotoViewerActionBar({
    this.isFavorite = false,
    this.infoOpen = false,
    this.onShare,
    this.onFavorite,
    this.onInfo,
    this.onDelete,
    super.key,
  });

  /// The smallest square each action answers taps in.
  static const double minTapTarget = 44;

  /// Whether the photo is a favorite, which words the action Unfavorite.
  final bool isFavorite;

  /// Whether the photo's details are showing, which selects Info.
  final bool infoOpen;

  /// Opens the share sheet. Null leaves the action out.
  final VoidCallback? onShare;

  /// Favorites the photo, or takes it out of Favorites while [isFavorite].
  /// Null leaves the action out.
  final VoidCallback? onFavorite;

  /// Shows or hides the photo's details. Null leaves the action out.
  final VoidCallback? onInfo;

  /// Moves the photo to the trash. Null leaves the action out.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final actions =
        <
          ({
            String key,
            IconData icon,
            String label,
            bool? selected,
            VoidCallback onPressed,
          })
        >[
          if (onShare case final onShare?)
            (
              key: 'photo_viewer_action_share',
              icon: QuarkIcons.share_outlined,
              label: 'Share',
              selected: null,
              onPressed: onShare,
            ),
          if (onFavorite case final onFavorite?)
            (
              key: 'photo_viewer_action_favorite',
              icon: isFavorite ? QuarkIcons.star : QuarkIcons.star_border,
              label: isFavorite ? 'Unfavorite' : 'Favorite',
              selected: null,
              onPressed: onFavorite,
            ),
          if (onInfo case final onInfo?)
            (
              key: 'photo_viewer_action_info',
              icon: infoOpen ? QuarkIcons.info : QuarkIcons.info_outline,
              label: 'Info',
              selected: infoOpen,
              onPressed: onInfo,
            ),
          if (onDelete case final onDelete?)
            (
              key: 'photo_viewer_action_delete',
              icon: QuarkIcons.delete_outline,
              label: 'Delete',
              selected: null,
              onPressed: onDelete,
            ),
        ];

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // Equal shares of the width, so a long label gives up letters
              // rather than overflowing a narrow phone (#1599).
              for (final action in actions)
                Expanded(
                  child: Semantics(
                    selected: action.selected,
                    child: Tooltip(
                      message: action.label,
                      child: TextButton(
                        key: ValueKey(action.key),
                        onPressed: action.onPressed,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size.square(minTapTarget),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(action.icon, size: 22),
                            const SizedBox(height: 2),
                            Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
