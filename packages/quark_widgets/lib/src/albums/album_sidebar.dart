import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/album_item.dart';
import '../theme/quark_tokens.dart';
import 'album_tree_tile.dart';

/// The album section of a sidebar: an "Albums" header with a create button,
/// and the album tree underneath.
///
/// Holds nothing. The albums, the selection, and which branches are expanded
/// all come in, and every action goes out, so the caller can reload the list,
/// expand a branch, or open a context menu of its own. System albums get
/// their own glyph (a star for favorites) and no long press, since the server
/// maintains them rather than the user.
///
/// By default the list fills its parent and scrolls on its own. Set
/// [shrinkWrap] wherever the parent hands it unbounded height, such as a
/// sliver, where filling is a hard layout error (#1599).
///
/// Key prefixes: `album_create` on the create button, and every row's own
/// `album_tile_<id>` and `album_expand_<id>` from [AlbumTreeTile].
///
/// ```dart
/// AlbumSidebar(
///   albums: controller.albums,
///   isLoading: controller.albumsLoading,
///   expandedIds: controller.expandedAlbumIds,
///   onAlbumSelected: openAlbum,
///   onToggleExpanded: controller.toggleAlbumExpanded,
///   onCreateAlbum: promptForNewAlbum,
///   onAlbumLongPress: showAlbumMenu,
/// );
/// ```
class AlbumSidebar extends StatelessWidget {
  /// Creates the album section over [albums].
  const AlbumSidebar({
    required this.albums,
    required this.expandedIds,
    required this.onAlbumSelected,
    required this.onToggleExpanded,
    required this.onCreateAlbum,
    this.onAlbumLongPress,
    this.selectedAlbumId,
    this.isLoading = false,
    this.error,
    this.shrinkWrap = false,
    super.key,
  });

  /// The root albums, in display order, each with its sub-albums.
  final List<AlbumItem> albums;

  /// The ids of every expanded album.
  final Set<int> expandedIds;

  /// Called with the album whose row was tapped.
  final ValueChanged<AlbumItem> onAlbumSelected;

  /// Called with the id whose chevron was tapped.
  final ValueChanged<int> onToggleExpanded;

  /// Called when the create button is tapped.
  final VoidCallback onCreateAlbum;

  /// Called with a user album that was long-pressed, for a context menu.
  /// Never called for a system album.
  final ValueChanged<AlbumItem>? onAlbumLongPress;

  /// The id highlighted as selected, or null for none.
  final int? selectedAlbumId;

  /// Whether the albums are loading. Shows a progress bar in place of the
  /// list.
  final bool isLoading;

  /// A user-facing message for a load that failed, or null.
  final String? error;

  /// Size to the list's own height instead of filling the parent.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final hint = TextStyle(
      fontSize: 13,
      color: colorScheme.onSurface.withValues(alpha: 0.4),
    );
    final hintPadding = EdgeInsets.symmetric(
      horizontal: tokens.spacingSm + tokens.spacingXs,
      vertical: tokens.spacingXs,
    );

    final list = ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: shrinkWrap,
      // Already inside an outer scroll view when shrink-wrapped; a nested
      // scrollable on the same axis would fight it for drag gestures.
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return AlbumTreeTile(
          album: album,
          selectedAlbumId: selectedAlbumId,
          expandedIds: expandedIds,
          onSelected: onAlbumSelected,
          onToggleExpanded: onToggleExpanded,
          onLongPress: album.isSystem ? null : onAlbumLongPress,
          systemIcon: album.isSystem
              ? (album.isFavorites
                    ? QuarkIcons.star_rounded
                    : QuarkIcons.pending_actions_outlined)
              : null,
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacingSm + tokens.spacingXs,
            vertical: tokens.spacingXs + tokens.spacingXs / 2,
          ),
          child: Row(
            children: [
              Text(
                'Albums',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const ValueKey('album_create'),
                icon: const Icon(QuarkIcons.add_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'New album',
                onPressed: onCreateAlbum,
              ),
            ],
          ),
        ),
        if (isLoading)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacingSm + tokens.spacingXs,
            ),
            child: const LinearProgressIndicator(),
          )
        else if (error != null)
          Padding(
            padding: hintPadding,
            child: Text(error, style: hint),
          )
        else if (albums.isEmpty)
          Padding(
            padding: hintPadding,
            child: Text('No albums yet', style: hint),
          )
        else if (shrinkWrap)
          list
        else
          Expanded(child: list),
        SizedBox(height: tokens.spacingSm),
        Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.5)),
      ],
    );
  }
}
