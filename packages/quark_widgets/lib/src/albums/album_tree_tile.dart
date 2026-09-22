import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/album_item.dart';
import '../theme/quark_tokens.dart';

/// One album row, indented by depth, with its expanded sub-albums underneath.
///
/// Expansion is not the tile's to keep: [expandedIds] comes in and
/// [onToggleExpanded] goes out, so a page can expand a branch programmatically
/// and the state survives the list being rebuilt. The tile recurses into
/// [AlbumItem.children], passing every input down, so a whole tree is one
/// widget per root.
///
/// Give it [onMenu] and every row gets a `more_vert` button, and a long press
/// or right-click on the row does the same thing, so a mouse user can find the
/// album's actions as easily as a touch user (#2261, #2262).
///
/// Key prefixes: `album_tile_<id>` on the row, `album_expand_<id>` on the
/// disclosure chevron, which is only rendered when the album has children,
/// and `album_menu_<id>` on the menu button, which is only rendered with
/// [onMenu].
///
/// ```dart
/// AlbumTreeTile(
///   album: album,
///   selectedAlbumId: controller.selectedAlbumId,
///   expandedIds: controller.expandedAlbumIds,
///   onSelected: controller.selectAlbum,
///   onToggleExpanded: controller.toggleAlbumExpanded,
///   onMenu: showAlbumMenu,
/// );
/// ```
class AlbumTreeTile extends StatelessWidget {
  /// Creates a row for [album] and its expanded descendants.
  const AlbumTreeTile({
    required this.album,
    required this.selectedAlbumId,
    required this.expandedIds,
    required this.onSelected,
    required this.onToggleExpanded,
    this.onMenu,
    this.depth = 0,
    this.systemIcon,
    super.key,
  });

  /// The album this row is for, with its sub-albums in
  /// [AlbumItem.children].
  final AlbumItem album;

  /// The [AlbumItem.id] currently selected anywhere in the tree, or null when
  /// nothing is.
  final int? selectedAlbumId;

  /// The ids of every expanded album. Membership decides both the chevron
  /// direction and whether children are rendered.
  final Set<int> expandedIds;

  /// Called with the album whose row was tapped.
  final ValueChanged<AlbumItem> onSelected;

  /// Called with the [AlbumItem.id] whose chevron was tapped. The caller adds
  /// or removes it from [expandedIds].
  final ValueChanged<int> onToggleExpanded;

  /// Called with the album whose menu button (`album_menu_<id>`) was tapped,
  /// or whose row was long-pressed or right-clicked, for a context menu. Null
  /// renders no button and leaves both gestures unhandled, which is what
  /// system albums want.
  final ValueChanged<AlbumItem>? onMenu;

  /// How deep this row sits in the tree, which sets its indent. Callers pass
  /// zero for a root; the tile increments it for its own children.
  final int depth;

  /// Replaces the album glyph, for a system album with its own icon.
  /// Descendants are not given it.
  final IconData? systemIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final isSelected = selectedAlbumId == album.id;
    final hasChildren = album.children.isNotEmpty;
    final isExpanded = expandedIds.contains(album.id);
    final indent = depth * tokens.spacingMd;
    final radius = BorderRadius.circular(tokens.radiusMd);
    final onMenu = this.onMenu;
    final openMenu = onMenu == null ? null : () => onMenu(album);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: ValueKey('album_tile_${album.id}'),
          onTap: () => onSelected(album),
          onLongPress: openMenu,
          onSecondaryTap: openMenu,
          borderRadius: radius,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: radius,
            ),
            padding: EdgeInsets.only(
              left: tokens.spacingSm + indent,
              right: tokens.spacingSm,
              top: tokens.spacingXs + tokens.spacingXs / 2,
              bottom: tokens.spacingXs + tokens.spacingXs / 2,
            ),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    key: ValueKey('album_expand_${album.id}'),
                    onTap: () => onToggleExpanded(album.id),
                    child: Icon(
                      isExpanded
                          ? QuarkIcons.expand_more_rounded
                          : QuarkIcons.chevron_right_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  const SizedBox(width: 16),
                SizedBox(width: tokens.spacingXs),
                Icon(
                  systemIcon ?? QuarkIcons.photo_album_outlined,
                  size: 16,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: tokens.spacingSm),
                Expanded(
                  child: Text(
                    album.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (album.itemCount > 0)
                  Text(
                    '${album.itemCount}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                if (openMenu != null)
                  IconButton(
                    key: ValueKey('album_menu_${album.id}'),
                    tooltip: 'Actions for ${album.name}',
                    icon: const Icon(QuarkIcons.more_vert),
                    iconSize: 16,
                    // The row is 13px text; a default 48px button would
                    // double its height.
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    color: colorScheme.onSurfaceVariant,
                    onPressed: openMenu,
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded && hasChildren)
          for (final child in album.children)
            AlbumTreeTile(
              album: child,
              selectedAlbumId: selectedAlbumId,
              expandedIds: expandedIds,
              onSelected: onSelected,
              onToggleExpanded: onToggleExpanded,
              onMenu: onMenu,
              depth: depth + 1,
            ),
      ],
    );
  }
}
